{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeSynonymInstances  #-}
{-# LANGUAGE ViewPatterns          #-}
module Diagrams.Backend.PGF.Render
  ( PGF (..)
  , Options (..)
  -- * Lenses
  , template
  , surface
  , sizeSpec
  , sizeSpecToBounds
  -- , preserveLineWidth
  , readable
  ) where

import           Control.Lens              (lens, (.=), (%=), (^.), op, view, 
                                            set, Lens', use)
import           Control.Monad             (when)
import           Data.Default
import           Data.Maybe                (isJust)
import           Data.Typeable
import           Diagrams.Prelude          hiding (r2, view)
import qualified Diagrams.Prelude          as D
import           Diagrams.TwoD.Image
import           Diagrams.TwoD.Adjust      (adjustDiaSize2D)
import           Diagrams.TwoD.Path
import           Diagrams.TwoD.Text
import qualified Blaze.ByteString.Builder  as Blaze

import qualified Graphics.Rendering.PGF        as P
import           Diagrams.Backend.PGF.Surface

-- | This data declaration is simply used as a token to distinguish
--   this rendering engine.
data PGF = PGF
  deriving (Show, Typeable)


instance Backend PGF R2 where
  data Render  PGF R2 = P (P.RenderM ())
  type Result  PGF R2 = Blaze.Builder
  data Options PGF R2 = PGFOptions
      { _template          :: Surface    -- ^ Surface you want to use.
      , _sizeSpec          :: SizeSpec2D -- ^ The requested size.
      , _readable          :: Bool       -- ^ Pretty print output.
      , _preserveLineWidth :: Bool       -- ^ Do not freeze before rendering.
      , _preserveDashing   :: Bool       -- ^ Adjust dashing widths.
      , _lineWidthAdjust   :: Double     -- ^ lineWidthFactor
      , _dashingAdjust     :: Double     -- ^ lineWidthFactor
      }

  withStyle _ s t (P r) = P . P.scope $ do
    P.applyTransform t
    P.style %= (<> s)
    setClipPaths <~ op Clip
    r

  doRender _ options (P r) =
      P.renderWith (options^.surface) (options^.readable) bounds r
      where bounds = sizeSpecToBounds (options^.sizeSpec)
  
  adjustDia =
      adjustDiaSize2D (view sizeSpec) (set sizeSpec)

sizeSpecToBounds :: SizeSpec2D -> (Double, Double)
sizeSpecToBounds spec = case spec of
   Width w  -> (w,w)
   Height h -> (h,h)
   Dims w h -> (w,h)
   Absolute -> (100,100)

instance Default (Options PGF R2) where
  def = PGFOptions
          { _template          = def
          , _sizeSpec          = Absolute
          , _readable          = True
          , _preserveLineWidth = True
          , _preserveDashing   = True
          -- , _transformText     = True
          , _dashingAdjust     = 1
          , _lineWidthAdjust   = 1
          }

-- | Lens to change the template, aka surface defined in Diagrams.Backend.PGF.Surface
template :: Lens' (Options PGF R2) Surface
template = lens getTemplate setTemplate
  where
    getTemplate (PGFOptions { _template = t }) = t
    setTemplate o t = o { _template = t }

surface :: Lens' (Options PGF R2) Surface
surface = template

sizeSpec :: Lens' (Options PGF R2) SizeSpec2D
sizeSpec = lens getSize setSize
  where getSize (PGFOptions { _sizeSpec = s }) = s
        setSize o s = o { _sizeSpec = s }

-- | Not yet implimented.
-- preserveLineWidth :: Lens' (Options PGF R2) Bool
-- preserveLineWidth = lens getter setter
--   where getter (PGFOptions { _preserveLineWidth = s }) = s
--         setter o s = o { _preserveLineWidth = s }

-- transformText :: Lens' (Options PGF R2) Bool
-- transformText = lens getter setter
--   where getter (PGFOptions { _transformText = s }) = s
--         setter o s = o { _transformText = s }

-- | Pretty print the output with indented lines, default is true
readable :: Lens' (Options PGF R2) Bool
readable = lens getR setR
  where
    getR (PGFOptions { _readable = r }) = r
    setR o r = o { _readable = r }

-- defStyle :: Style R2
-- defStyle = mempty # lineWidthA def # lineColorA def
--                   # lineCap def # lineJoin def 
--                   # lineMiterLimitA def

-- set default values outside scope
-- initialStyle :: P.Render
-- initialStyle = do
--   P.setLineWidth <~ getLineWidth
--   P.setLineColor <~ getLineColor
--   P.setLineCap   <~ getLineCap
--   P.setLineJoin  <~ getLineJoin

-- instance Hashable (Options Cairo R2)

instance Monoid (Render PGF R2) where
  mempty  = P $ return ()
  (P r1) `mappend` (P r2) = P (r1 >> r2)

renderP :: (Renderable a PGF, V a ~ R2) => a -> P.RenderM ()
renderP (render PGF -> P r) = r
  
-- | Use the path that has already been drawn in scope. The path is stroked if 
--   linewidth > 0.0001 and if filled if a colour is defined.
--
--   All stroke and fill properties from the cuuent @style@ are also output here.
draw :: P.RenderM ()
draw = do
  doFill <- shouldFill
  when doFill $ do
    setFillColor' <~ getFillColor
    P.setFillRule <~ getFillRule
  --
  doStroke <- shouldStroke
  when doStroke $ do
    setLineColor'  <~ getLineColor -- stoke opacity needs to be set
    P.setLineJoin  <~ getLineJoin
    P.setLineWidth <~ getLineWidth
    P.setLineCap   <~ getLineCap
    P.setDash      <~ getDashing
  -- 
  P.usePath doFill doStroke False

-- helper function to easily get options and set them
(<~) :: (AttributeClass a) => (b -> P.RenderM ()) -> (a -> b) -> P.RenderM ()
command <~ getF = do
  s <- use P.style
  let mAttr = (getF <$>) . getAttr $ s
  maybe (return ()) command mAttr

setFillColor' :: (Color c) => c -> P.RenderM ()
setFillColor' c = do
  s <- use P.style
  P.setFillColor $ applyOpacity c s

setLineColor' :: (Color c) => c -> P.RenderM ()
setLineColor' c = do
  s <- use P.style
  P.setLineColor $ applyOpacity c s

-- | Apply the opacity from a style to a given color.
applyOpacity :: Color c => c -> Style v -> AlphaColour Double
applyOpacity c s = dissolve (maybe 1 getOpacity (getAttr s)) (toAlphaColour c)

-- | Queries the current style and decides if the path should be filled. Paths 
--   are filled if a color is defined
shouldFill :: P.RenderM Bool
shouldFill = do
  fColor <- (getFillColor <$>) . getAttr <$> use P.style
  ignore <- use P.ignoreFill
  --
  return $ not ignore && isJust fColor

-- | Queries the current style and decides if the path should be stroked. Paths 
--   are stroked when lw > 0.0001
shouldStroke :: P.RenderM Bool
shouldStroke = do
  mLWidth <- (getLineWidth <$>) . getAttr <$> use P.style
  --
  return $ maybe True (> P.epsilon) mLWidth

setClipPaths :: [Path R2] -> P.Render
setClipPaths = mapM_ setClipPath

setClipPath :: Path R2 -> P.Render
setClipPath (Path trs) = do
  mapM_ renderTrail trs
  P.clip
  where
    renderTrail (viewLoc -> (unp2 -> p, tr)) = do
      P.moveTo (D.r2 p)
      renderP tr

renderPath :: Path R2 -> P.RenderM ()
renderPath (Path trs) = do
  when (any (isLine . unLoc) trs) $ P.ignoreFill .= True
  mapM_ renderTrail trs
  draw
  where
    renderTrail (viewLoc -> (unp2 -> p, tr)) = do
      P.moveTo (D.r2 p)
      renderP tr


--------------------------------------------------
-- Renderable instances

instance Renderable (Segment Closed R2) PGF where
  render _ (Linear (OffsetClosed v))       = P $ P.lineTo v
  render _ (Cubic v1 v2 (OffsetClosed v3)) = P $ P.curveTo v1 v2 v3

instance Renderable (Trail R2) PGF where
  render _ t = withLine (render' . lineSegments) t where
    render' segs = P $ do
        mapM_ renderP segs
        when (isLoop t) P.closePath

instance Renderable (Path R2) PGF where
  render _ = P . renderPath

instance Renderable Text PGF where
  render _ = P . renderText

-- | Renders text. Colour is set by fill colour. Opacity is inheritied from 
--   scope fill opacity. Does not support full alignment. Text is not escaped.
--   Implimentation incomplete.
renderText :: Text -> P.Render
renderText (Text tr tAlign str) = do
  setFillColor' <~ getFillColor
  --
  doTxtTrans <- view P.txtTrans
  P.applyTransform tr
  if doTxtTrans
    then (P.applyScale . (/8))  <~ getFontSize
      -- (/8) was obtained from trail and error
    else P.resetNonTranslations
  --
  P.renderText (P.setTextAlign tAlign) $ do
    P.setFontWeight <~ getFontWeight
    P.setFontSlant  <~ getFontSlant
    P.rawString str

instance Renderable Image PGF where
  render _ (Image file _{-size-} _{-tr-}) = P $ P.image file

