-- | Saves received values to the disk somewhere
--
module CountVonCount.CsvLog
    ( runCsvLog
    ) where

import Control.Monad (when)
import System.IO (openFile, IOMode (AppendMode), hPutStrLn, hClose)
import Text.Printf (printf)
import Control.Concurrent.Chan (Chan)

import CountVonCount.Chan
import CountVonCount.Types
import CountVonCount.Configuration

-- | Run a persistence thread that saves values to a CSV file
--
runCsvLog :: Configuration  -- ^ Global configuration
          -> Chan Command   -- ^ Channel to read from
          -> IO ()          -- ^ Blocks forever
runCsvLog configuration chan = do
    handle <- openFile filePath AppendMode
    readChanLoop chan $ \(Measurement (mac, (time, position, rssi))) ->
        when (allowedMac mac configuration) $
            hPutStrLn handle $
                printf "%s,%f,%f,%d" (pmac mac) time position rssi
    hClose handle
  where
    pmac = show . flip prettifyMac configuration
    filePath = configurationCsvLog configuration