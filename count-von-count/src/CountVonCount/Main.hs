--------------------------------------------------------------------------------
{-# LANGUAGE ScopedTypeVariables #-}
module Main
    ( main
    ) where


--------------------------------------------------------------------------------
import           Control.Concurrent             (forkIO)
import qualified Data.Aeson                     as A
import           Data.Foldable                  (forM_)
import           Data.Time                      (getCurrentTime)
import qualified Network.WebSockets             as WS
import qualified Network.WebSockets.Util.PubSub as WS


--------------------------------------------------------------------------------
import           CountVonCount.Boxxy
import           CountVonCount.Config
import           CountVonCount.Counter
import           CountVonCount.Counter.Core
import           CountVonCount.EventBase
import qualified CountVonCount.Log              as Log
import qualified CountVonCount.Persistence      as P
import           CountVonCount.Sensor
import qualified CountVonCount.Sensor           as Sensor
import           CountVonCount.Sensor.Filter
import qualified CountVonCount.Web              as Web
import qualified CountVonCount.Web.Views        as Views


--------------------------------------------------------------------------------
main :: IO ()
main = do
    putStrLn "Count Von Count starting in 1..2..3..."
    config    <- readConfigFile "count-von-count.yaml"
    logger    <- Log.open (configLog config) True
    eventBase <- newEventBase logger
    database  <- P.newDatabase "count-von-count.db"
    replayLog <- Log.open (configReplayLog config) False
    Log.string logger "CountVonCount.Main.main" "count-von-count started"

    -- Create the pubsub system
    pubSub <- WS.newPubSub

    -- Initialize boxxy
    boxxies <- newBoxxies logger (configBoxxies config) $ \b -> do
        teams    <- P.getAllTeams database
        time     <- getCurrentTime
        stations <- P.getAllStations database
        putConfig b (configStartTime config) (configCircuitLength config)
                stations teams time

    -- Connecting the sensor to the counter
    subscribe eventBase "sensor handler" $ \event -> do
        let filterSensorEvent' = filterSensorEvent database logger
                (configRssiThreshold config)
        Log.raw replayLog $ toReplay event
        filtered <- filterSensorEvent' event
        forM_ filtered $ publish eventBase

    -- Start the sensor
    _ <- forkIO $ Sensor.listen logger eventBase (configSensorPort config)

    -- Start the counter
    counter <- newCounter
    subscribeCounter counter (configCircuitLength config)
        (configMaxSpeed config) logger eventBase database
        {-
        (counterHandler (configCircuitLength config) logger
            boxxies pubSub) sensorChan
        -}

    -- Publish counter events to browser
    subscribe eventBase "WS counter handler" $
        \(team, cstate, _ :: CounterEvent) ->
            WS.publish pubSub $ WS.textData $ A.encode $
            Views.counterState (configCircuitLength config) team (Just cstate)

    -- Publish counter events to boxxies
    subscribe eventBase "boxxies counter handler" $
        \(team, _ :: CounterState, event) ->
            withBoxxies logger boxxies $ \b -> case event of
                Lap time speed                 ->
                    putLaps b team time 1 (Just speed) Nothing
                Progression time station speed ->
                    putPosition b team time station speed

    -- Start the baton watchdog
    _ <- forkIO $ watchdog counter eventBase
        (configBatonWatchdogInterval config)
        (configBatonWatchdogLifespan config)

    -- Publish baton watchdog events to browser
    subscribe eventBase "baton handler" $ \deadBatons -> do
        deadBatons' <- mapM (P.getBaton database) deadBatons
        WS.publish pubSub $ WS.textData $ A.encode $
            Views.deadBatons deadBatons'

    Web.listen config logger database pubSub counter boxxies

    Log.string logger "CountVonCount.Main.main" "Closing..."
    P.closeDatabase database
    Log.close replayLog
    Log.close logger
