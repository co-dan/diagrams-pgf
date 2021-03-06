{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Puting.PGF.Sys
-- Maintainer  :  c.chalmers@me.com
--
-- Interface to the system layer of PGF. This is intented to be the rendering 
-- engine for standalone PGF diagrams because of it's difficuily when working 
-- with it. Currently incomplete.
--
------------------------------------------------------------------------------
module Graphics.Puting.PGF.Sys
  ( render
  , PutM
  , Put
  , raw
  , rawString
  -- * Environments
  , scope
  , epsilon
  -- * Paths
  , lineTo
  , curveTo
  , moveTo
  , closePath
  , clip
  , stroke
  , fill
  -- * Strokeing Options
  , dash
  , lw
  , cap
  , join
  , miterLimit
  , strokeColor
  , strokeOpacity
  -- * Fill Options
  , fillColor
  , eoRule
  , fillRule
  , fillOpacity
  -- * Transformations
  , transform
  , scale
  , shift
  -- * images
  -- * Text
  , paperSize
  ) where

import Data.Monoid
import Blaze.ByteString.Builder as Blaze
import Blaze.ByteString.Builder.Char.Utf8 as Blaze
import Data.Double.Conversion.ByteString
import Data.ByteString.Char8 (ByteString)
import Data.List (intersperse)

import Diagrams.Attributes (LineCap(..), LineJoin(..), Dashing(..))
import Diagrams.TwoD.Path (FillRule(..))
import Diagrams.TwoD.Types (R2, unr2)
-- import Diagrams.TwoD.Text
-- import Diagrams.TwoD.Image

data PairS a = PairS a !Builder

sndS :: PairS a -> Builder
sndS (PairS _ b) = b

-- | The PutM type. A Writer monad over the efficient Builder monoid.
newtype PutM a = Put { unPut :: PairS a }

-- | Put merely lifts Builder into a Writer monad, applied to ().
type Put = PutM ()

instance Functor PutM where
        fmap f m = Put $ let PairS a w = unPut m in PairS (f a) w
        {-# INLINE fmap #-}

-- instance Applicative PutM where
--         pure    = return
--         m <*> k = Put $
--             let PairS f w  = unPut m
--                 PairS x w' = unPut k
--             in PairS (f x) (w `mappend` w')

-- Standard Writer monad, with aggressive inlining
instance Monad PutM where
    return a = Put $ PairS a mempty
    {-# INLINE return #-}

    m >>= k  = Put $
        let PairS a w  = unPut m
            PairS b w' = unPut (k a)
        in PairS b (w `mappend` w')
    {-# INLINE (>>=) #-}

    m >> k  = Put $
        let PairS _ w  = unPut m
            PairS b w' = unPut k
        in PairS b (w `mappend` w')
    {-# INLINE (>>) #-}


render :: PutM a -> Builder
render = sndS . unPut

-- builder functions

tell :: Blaze.Builder -> Put
tell b = Put $ PairS () b
{-# INLINE tell #-}

raw :: ByteString -> Put
raw = tell . Blaze.fromByteString

rawString :: String -> Put
rawString = tell . Blaze.fromString

sys :: ByteString -> Put
sys c = raw "\\pgfsys@" >> raw c

rawChar :: Char -> Put
rawChar = tell . Blaze.fromChar

ln :: Put -> Put
ln = (>> rawChar '\n')

-- | Wrap a `Put` in { .. }.
bracers :: Put -> Put
bracers r = do
  rawChar '{'
  r
  rawChar '}'

commaIntersperse :: [Put] -> Put
commaIntersperse = sequence_ . intersperse (rawChar ',')

-- * number and points

p :: R2 -> Put
p = p' . unr2

p' :: (Double,Double) -> Put
p' (x,y) = do
  bracers (px x)
  bracers (px y)

n :: Double -> Put
n = bracers . show4

cm :: Double -> Put
cm = (>> raw "cm") . show4

show4 :: Double -> Put
show4 = raw . toFixed 4

px :: Double -> Put
px = (>> raw "px") . show4

-- | ε = 0.0001 is the limit at which lines are no longer stroked.
epsilon :: Double
epsilon = 0.0001


-- * PGF environments

-- | Wrap the Puting in a scope.
scope :: Put -> Put
scope r = do
  beginScope
  r
  endScope

-- | Header for starting a scope.
beginScope :: Put
beginScope = ln $ sys "beginscope"

-- | Footer for ending a scope.
endScope :: Put
endScope = ln $ sys "endscope"

-- transformations

transform :: (Double,Double,Double,Double,Double,Double) -> Put
transform (a,b,c,d,e,f) = ln $ do
  sys "transformcm"
  mapM_ n [a,b,c,d]
  p' (e,f)

shift :: R2 -> Put
shift v = ln $ do
  sys "transformshift"
  p v

scale :: (Double,Double) -> Put
scale s = ln $ do
  sys "transformxyscale"
  p' s


-- Path commands

moveTo :: R2 -> Put
moveTo v = ln $ do
  sys "moveto"
  p v

lineTo :: R2 -> Put
lineTo v = ln $ do
  sys "lineto"
  p v

curveTo :: R2 -> R2 -> R2 -> Put
curveTo v2 v3 v4 = ln $ do
  sys "curveto"
  mapM_ p [v2,v3,v4]

-- using paths

closePath :: Put
closePath = ln $ sys "pathclose"

stroke :: Put
stroke = ln $ sys "stroke"

-- strokeClose :: Put
-- strokeClose = ln $ sys "closestroke"

fill :: Put
fill = ln $ sys "fill"

clip :: Put
clip = ln $ do
  sys "clipnext"
  sys "discardpath"
  -- this is the only way diagrams spcifies clips

lw :: Double -> Put 
lw w = ln $ do
  sys "setlinewidth"
  n w

-- properties

cap :: LineCap -> Put
cap c = ln . sys $ case c of
  LineCapButt   -> "buttcap"
  LineCapRound  -> "roundcap"
  LineCapSquare -> "rectcap"

join :: LineJoin -> Put
join j = ln . sys $ case j of
  LineJoinBevel -> "beveljoin"
  LineJoinRound -> "roundjoin"
  LineJoinMiter -> "miterjoin"

miterLimit :: Double -> Put
miterLimit l = ln $ do
  sys "setmiterlimit"
  n l

dash :: Dashing -> Put
dash (Dashing ds ph) = dash' ds ph

dash' :: [Double] -> Double -> Put
dash' ds ph = ln $ do
  bracers . commaIntersperse $ map cm ds
  bracers $ cm ph

eoRule :: Put
eoRule = raw "\\ifpgfsys@eorule" -- not sure about this

fillRule :: FillRule -> Put
fillRule EvenOdd = eoRule
fillRule _       = return ()

-- * Colours

strokeColor :: Double -> Double -> Double -> Put
strokeColor r g b = ln $ do
  sys "color@rgb@stroke"
  mapM_ n [r,g,b]

fillColor :: Double -> Double -> Double -> Put
fillColor r g b = do
  sys "color@rgb@stroke"
  mapM_ n [r,g,b]

strokeOpacity :: Double -> Put
strokeOpacity o = ln $ do
  sys "stroke@opacity"
  n o

fillOpacity :: Double -> Put
fillOpacity o = ln $ do
  sys "fill@opacity"
  n o

paperSize :: (Double, Double) -> Put
paperSize s = ln $ p' s

