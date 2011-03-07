module CountVonCount.Counter
    ( CounterState
    , emptyCounterState
    , CounterM
    , counter
    , runCounter
    ) where

import Control.Monad.State (State, get, put, runState)
import Data.Monoid (mempty)
import Control.Applicative ((<$>))

import CountVonCount.Types
import CountVonCount.FiniteChan
import CountVonCount.DataSet
import CountVonCount.Analyzer

data CounterState = CounterState
    { counterDataSet      :: DataSet
    , counterLastPosition :: Maybe Position
    } deriving (Show)

emptyCounterState :: CounterState
emptyCounterState = CounterState mempty Nothing

type CounterM = State CounterState

-- | Run a counter
--
counter :: Measurement -> CounterM (Maybe Score)
counter measurement = do
    -- Read a measurement
    let (_, position) = measurement

    -- Obtain state and create a possible next dataset
    dataSet <- counterDataSet <$> get
    lastPosition <- counterLastPosition <$> get
    let dataSet' = addMeasurement measurement dataSet

        -- Check if we have a possible lap
        score = if maybeLap lastPosition position
                    -- Maybe a lap, check for it
                    then Just $ analyze dataSet
                    -- Certainly no lap
                    else Nothing
                    
    -- Clear the dataset if necessary
    if isLap score
        then put $ CounterState cleared  $ Just position
        else put $ CounterState dataSet' $ Just position

    -- Return found score
    return score
  where
    maybeLap Nothing  _                   = False
    maybeLap (Just lastPosition) position = lastPosition > position

    -- Check if a score is a lap
    isLap Nothing            = False
    isLap (Just (Refused _)) = False
    isLap _                  = True

    -- A cleared dataset
    cleared = addMeasurement measurement mempty

-- | Run a counter
--
runCounter :: Team                                 -- ^ Identifier
           -> FiniteChan Measurement               -- ^ In Channel
           -> FiniteChan (Timestamp, Team, Score)  -- ^ Out Channel
           -> IO ()                                -- ^ Blocks forever
runCounter team inChan outChan = do
    _ <- runFiniteChan inChan emptyCounterState $ \measurement state -> do
        -- Run the pure counter and optionally send the result
        let (timestamp, _) = measurement
            (result, state') = runState (counter measurement) state
        case result of Nothing -> return ()
                       Just s  -> writeFiniteChan outChan (timestamp, team, s)

        -- Yield the state for the next iteration
        return state'
    return ()