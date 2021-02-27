module Lion.Core 
  ( ToCore(..)
  , fromMem
  , FromCore(..)
  , toMem
  , toRvfi
  , P.ToMem(..)
  , core
  ) where

import Clash.Prelude
import Control.Lens
import Data.Maybe
import Data.Monoid
import Lion.Rvfi
import qualified Lion.Pipe as P

-- | Core input
data ToCore dom = ToCore
  { _fromMem :: Signal dom (BitVector 32)
  }
makeLenses ''ToCore

-- | Core outputs
data FromCore dom = FromCore
  { _toMem  :: Signal dom (Maybe P.ToMem)
  , _toRvfi :: Signal dom Rvfi
  }
makeLenses ''FromCore

-- | Core: run pipeline with register file
core
  :: HiddenClockResetEnable dom
  => ToCore dom
  -> FromCore dom
core toCore = FromCore
  { _toMem  = getFirst . P._toMem <$> fromPipe
  , _toRvfi = fromMaybe mkRvfi . getFirst . P._toRvfi <$> fromPipe
  }
  where
    fromPipe = P.pipe $ P.ToPipe <$> rs1Data <*> rs2Data <*> _fromMem toCore
    rs1Addr = fromMaybe 0 . getFirst . P._toRs1Addr <$> fromPipe
    rs2Addr = fromMaybe 0 . getFirst . P._toRs2Addr <$> fromPipe
    rdWrM = getFirst . P._toRd <$> fromPipe
    (rs1Data, rs2Data) = regBank rs1Addr rs2Addr rdWrM

-- | Register bank
regBank
  :: HiddenClockResetEnable dom
  => Signal dom (Unsigned 5)                        -- ^ Rs1 Addr
  -> Signal dom (Unsigned 5)                        -- ^ Rs2 Addr
  -> Signal dom (Maybe (Unsigned 5, BitVector 32))  -- ^ Rd Write
  -> Unbundled dom (BitVector 32, BitVector 32)     -- ^ (Rs1Data, Rs2Data)
regBank rs1Addr rs2Addr rdWrM = (regFile rs1Addr, regFile rs2Addr)
  where
    regFile = flip (readNew (blockRamPow2 (repeat 0))) rdWrM