-- | Communication with sensors (i.e. Gyrid)
{-# LANGUAGE BangPatterns, OverloadedStrings #-}
module CountVonCount.Sensor
    ( listen
    ) where

import Control.Applicative ((*>))
import Control.Arrow ((&&&))
import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import Control.Monad (forever)
import Control.Monad.Trans (liftIO)
import Data.Monoid (mappend)
import Data.Time (UTCTime, getCurrentTime, parseTime)
import System.Locale (defaultTimeLocale)
import Data.Map (Map)

import Data.ByteString (ByteString)
import Data.ByteString.Char8 ()
import Data.Enumerator (Iteratee, ($$), (=$))
import qualified Data.Attoparsec as A
import qualified Data.Attoparsec.Enumerator as AE
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.Enumerator as E
import qualified Data.Enumerator.List as EL
import qualified Data.Map as M
import qualified Data.Text.Encoding as T
import qualified Network.Socket as S
import qualified Network.Socket.ByteString as S
import qualified Network.Socket.Enumerator as SE

import CountVonCount.Types
import CountVonCount.Config

data SensorState = SensorState
    { stationMap :: Map Mac Station
    , batonMap   :: Map Mac Baton
    , sensorChan :: Chan SensorEvent
    }

listen :: Config
       -> Chan SensorEvent
       -> IO ()
listen conf chan = do
    putStrLn "Sensor: listening..."

    sock <- S.socket S.AF_INET S.Stream S.defaultProtocol
    _    <- S.setSocketOption sock S.ReuseAddr 1
    host <- S.inet_addr "0.0.0.0"
    S.bindSocket sock $ S.SockAddrInet (fromIntegral port) host
    S.listen sock 5

    let sensorState = constructState conf chan

    forever $ do
        (conn, _) <- S.accept sock
        _ <- forkIO $ ignore $ do
            S.sendAll conn "MSG,enable_rssi,true\r\n"
            S.sendAll conn "MSG,enable_cache,false\r\n"
        _ <- forkIO $ do
            E.run_ $ SE.enumSocket 256 conn $$
                E.sequence (AE.iterParser gyrid) =$ receive sensorState
            S.sClose conn
        return ()
  where
    ignore x = catch x $ const $ return ()
    port = configSensorPort conf

constructState :: Config -> Chan SensorEvent -> SensorState
constructState config chan = SensorState
    { stationMap = stMap
    , batonMap   = bMap
    , sensorChan = chan
    }
  where
    stMap = M.fromList $ fmap (stationMac &&& id) $ configStations config
    bMap  = M.fromList $ fmap (batonMac &&& id)   $ configBatons   config

receive :: SensorState
        -> Iteratee Gyrid IO ()
receive state = do
    g <- EL.head
    case g of
        Nothing                        -> return ()
        Just Ignored                   -> receive state
        Just (Replay time station mac) -> do
            let event = handler state time station mac
            liftIO $ writeToChan (sensorChan state) event
            receive state
        Just (Event station mac)       -> do
            time <- liftIO getCurrentTime
            let event = handler state time station mac
            liftIO $ writeToChan (sensorChan state) event
            receive state

writeToChan :: Chan SensorEvent -> Maybe SensorEvent -> IO ()
writeToChan _     Nothing     = return ()
writeToChan chan (Just event) = writeChan chan event

handler :: SensorState -> UTCTime -> Mac -> Mac -> Maybe SensorEvent
handler state time station baton = do
    st <- M.lookup station $ stationMap state
    bt <- M.lookup baton   $ batonMap   state
    return $ SensorEvent time st bt



data Gyrid
    = Event Mac Mac
    | Replay UTCTime Mac Mac
    | Ignored
    deriving (Show)

gyrid :: A.Parser Gyrid
gyrid = do
    line <- lineParser
    return $ case BC.split ',' line of
        ("MSG" : _)                       -> Ignored
        ("INFO" : _)                      -> Ignored
        ["REPLAY", !time, !station, !mac] ->
            case parseTime defaultTimeLocale "%s" (BC.unpack time) of
                Just t -> Replay t (parseMac station) (parseMac mac)
                _      -> Ignored
        [!station, _, !mac, _]            ->
            Event (parseMac station) (parseMac mac)
        _                                 -> Ignored
  where
    newline x  = x `B.elem` "\r\n"
    lineParser = A.skipWhile newline *> A.takeWhile (not . newline)

-- | Transform a mac without @:@ delimiters to one a mac with @:@ delimiters
parseMac :: ByteString -> Mac
parseMac bs = T.decodeUtf8 $ if ':' `BC.elem` bs then bs else parseMac' bs
  where
    parseMac' bs' = case BC.splitAt 2 bs' of
        (h, "")   -> h
        (h, rest) -> h `mappend` ":" `mappend` parseMac' rest
