{-# LANGUAGE OverloadedStrings #-}
module CountVonCount.Config
    ( BoxxyConfig (..)
    , Config (..)
    , defaultConfig
    , readConfigFile

      -- * Utility
    , findBaton
    ) where

import Control.Applicative ((<$>),(<*>))
import Control.Monad (mzero)
import Data.Maybe (fromMaybe)
import Data.List (find)

import Data.Aeson (FromJSON (..), ToJSON (..), (.=), (.:?), (.!=))
import Data.Yaml (decodeFile)
import qualified Data.Aeson as A

import CountVonCount.Types
import CountVonCount.Boxxy

data Config = Config
    { configCircuitLength :: Double
    , configMaxSpeed      :: Double
    , configSensorPort    :: Int
    , configLog           :: FilePath
    , configReplayLog     :: FilePath
    , configStations      :: [Station]
    , configBatons        :: [Baton]
    , configRssiThreshold :: Double
    , configBoxxies       :: [BoxxyConfig]
    } deriving (Show)

instance ToJSON Config where
    toJSON conf = A.object
        [ "circuitLength" .= configCircuitLength conf
        , "maxSpeed"      .= configMaxSpeed      conf
        , "sensorPort"    .= configSensorPort    conf
        , "log"           .= configLog           conf
        , "replayLog"     .= configReplayLog     conf
        , "stations"      .= configStations      conf
        , "batons"        .= configBatons        conf
        , "rssiThreshold" .= configRssiThreshold conf
        , "boxxies"       .= configBoxxies       conf
        ]

instance FromJSON Config where
    parseJSON (A.Object o) = Config <$>
        o .:? "circuitLength" .!= configCircuitLength defaultConfig <*>
        o .:? "maxSpeed"      .!= configMaxSpeed      defaultConfig <*>
        o .:? "sensorPort"    .!= configSensorPort    defaultConfig <*>
        o .:? "log"           .!= configLog           defaultConfig <*>
        o .:? "replayLog"     .!= configReplayLog     defaultConfig <*>
        o .:? "stations"      .!= configStations      defaultConfig <*>
        o .:? "batons"        .!= configBatons        defaultConfig <*>
        o .:? "rssiThreshold" .!= configRssiThreshold defaultConfig <*>
        o .:? "boxxies"       .!= configBoxxies       defaultConfig

    parseJSON _ = mzero

defaultConfig :: Config
defaultConfig = Config
    { configCircuitLength = 400
    , configMaxSpeed      = 12  -- 12m/s should be plenty?
    , configSensorPort    = 9001
    , configLog           = "log/count-von-count.log"
    , configReplayLog     = "log/replay.log"
    , configStations      = []
    , configBatons        = []
    , configRssiThreshold = -81
    , configBoxxies       = [defaultBoxxyConfig]
    }

readConfigFile :: FilePath -> IO Config
readConfigFile filePath = fromMaybe
    (error $ "Could not read config: " ++ filePath) <$> decodeFile filePath

findBaton :: Mac -> Config -> Maybe Baton
findBaton mac = find ((== mac) . batonMac) . configBatons
