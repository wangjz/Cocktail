/*
 * Cocktail, HTML rendering engine
 * http://haxe.org/com/libs/cocktail
 *
 * Copyright (c) Silex Labs
 * Cocktail is available under the MIT license
 * http://www.silexlabs.org/labs/cocktail-licensing/
*/
package cocktail.core.layer;

import cocktail.core.dom.Document;
import cocktail.core.dom.Node;
import cocktail.core.dom.NodeBase;
import cocktail.core.html.HTMLDocument;
import cocktail.core.html.HTMLElement;
import cocktail.core.html.ScrollBar;
import cocktail.core.renderer.ElementRenderer;
import cocktail.core.layout.computer.VisualEffectStylesComputer;
import cocktail.core.css.CoreStyle;
import cocktail.core.layout.LayoutData;
import cocktail.core.geom.Matrix;
import cocktail.core.graphics.GraphicsContext;
import cocktail.port.NativeElement;
import cocktail.core.geom.GeomData;
import cocktail.core.css.CSSData;
import haxe.Log;

/**
 * Each ElementRenderer belongs to a LayerRenderer representing
 * its position in the document in the z axis. LayerRenderer
 * are instantiated by ElementRenderer. Not all ElementRenderer
 * create their own layer, only those which can potentially overlap
 * other ElementRenderer, for instance ElementRenderer with a
 * non-static position (absolute, relative or fixed).
 * 
 * ElementRenderer which don't create their own LayerRenderer use
 * the one of their parent
 * 
 * The created LayerRenderers form the LayerRenderer tree,
 * paralleling the rendering tree.
 * 
 * The LayerRenderer tree is in charge of managing the stacking contexts
 * of the document which is a representation of the document z-index
 * as a stack of ElementRenderers, ordered by z-index.
 * 
 * LayerRenderer may establish a new stacking context, from the CSS 2.1
 * w3c spec : 
	 *  The order in which the rendering tree is painted onto the canvas 
	 * is described in terms of stacking contexts. Stacking contexts can contain
	 * further stacking contexts. A stacking context is atomic from the point of 
	 * view of its parent stacking context; boxes in other stacking contexts may
	 * not come between any of its boxes.
	 * 
	 * Each box belongs to one stacking context. Each positioned box in
	 * a given stacking context has an integer stack level, which is its position 
	 * on the z-axis relative other stack levels within the same stacking context.
	 * Boxes with greater stack levels are always formatted in front of boxes with
	 * lower stack levels. Boxes may have negative stack levels. Boxes with the same 
	 * stack level in a stacking context are stacked back-to-front according
	 * to document tree order.
	 * 
	 * The root element forms the root stacking context. Other stacking
	 * contexts are generated by any positioned element (including relatively
	 * positioned elements) having a computed value of 'z-index' other than 'auto'.
 * 
 * Ths structure of the LayerRenderer tree reflects the stacking contexts,
 * as when a child layer is appended to a layer, if the layer doesn't establish
 * a new stacking context, it is added to is paren instead.
 * 
 * TODO 3 : doc on stacking context is not really explicit
 * 
 * LayerRenderer are also responsible of hit testing and can return 
 * the top ElementRenderer at a given coordinate
 * 
 * @author Yannick DOMINGUEZ
 */
class LayerRenderer extends NodeBase<LayerRenderer>
{
	/**
	 * A reference to the ElementRenderer which
	 * created the LayerRenderer
	 */
	public var rootElementRenderer(default, null):ElementRenderer;
	
	/**
	 * Holds a reference to all of the child LayerRender which have a z-index computed 
	 * value of 0 or auto, which means that they are rendered in tree
	 * order of the DOM tree.
	 */
	private var _zeroAndAutoZIndexChildLayerRenderers:Array<LayerRenderer>;
	
	/**
	 * Holds a reference to all of the child LayerRenderer which have a computed z-index
	 * superior to 0. They are ordered in this array from least positive to most positive,
	 * which is the order which they must use to be renderered
	 */
	private var _positiveZIndexChildLayerRenderers:Array<LayerRenderer>;
	
	/**
	 * same as above for child LayerRenderer with a negative computed z-index. The array is
	 * ordered form most negative to least negative
	 */
	private var _negativeZIndexChildLayerRenderers:Array<LayerRenderer>;
	
	/**
	 * The graphics context onto which all the ElementRenderers
	 * belonging to this LayerRenderer are painted onto
	 */
	public var graphicsContext(default, null):GraphicsContext;
	
	/**
	 * Store the current width of the window. Used to check if the window
	 * changed size in between renderings
	 */
	private var _windowWidth:Int;
	
	/**
	 * Same as windowWidth for height
	 */
	private var _windowHeight:Int;
	
	/**
	 * A flag determining wether this LayerRenderer has its own
	 * GraphicsContext or use the one of its parent. It helps
	 * to determine if this LayerRenderer is responsible to perform
	 * oparation such as clearing its graphics context when rendering
	 */
	public var hasOwnGraphicsContext(default, null):Bool;
	
	/**
	 * A flag determining wether the layer renderer needs
	 * to do any rendering. As soon as an ElementRenderer
	 * from the LayerRenderer needs rendering, its
	 * LayerRenderer needs rendering
	 */
	private var _needsRendering:Bool;
	
	/**
	 * A flag determining wether the layer should
	 * update its graphics context, it is the case for
	 * instance when the layer is attached to the rendering
	 * tree
	 */
	private var _needsGraphicsContextUpdate:Bool;
	
	/**
	 * A flag determining for a LayerRenderer which 
	 * has its own graphic context, if the size of the
	 * bitmap data of its grapic context should be updated.
	 * 
	 * It is the case when the size of the viewport changes
	 * of when a new graphics context is created for this 
	 * LayerRenderer
	 */
	private var _needsBitmapSizeUpdate:Bool;
	
	/**
	 * A point used to determine wether an
	 * ElementRenderer is within a given bound
	 */
	private var _scrolledPoint:PointVO;
	
	/**
	 * class constructor. init class attributes
	 */
	public function new(rootElementRenderer:ElementRenderer) 
	{
		super();
		
		this.rootElementRenderer = rootElementRenderer;
		_zeroAndAutoZIndexChildLayerRenderers = new Array<LayerRenderer>();
		_positiveZIndexChildLayerRenderers = new Array<LayerRenderer>();
		_negativeZIndexChildLayerRenderers = new Array<LayerRenderer>();
		
		hasOwnGraphicsContext = false;
		
		_needsRendering = true;
		_needsBitmapSizeUpdate = true;
		_needsGraphicsContextUpdate = true;
		
		_windowWidth = 0;
		_windowHeight = 0;
		
		_scrolledPoint = new PointVO(0.0, 0.0);
	}
	
	/**
	 * clean up method
	 */
	public function dispose():Void
	{
		_zeroAndAutoZIndexChildLayerRenderers = null;
		_positiveZIndexChildLayerRenderers = null;
		_negativeZIndexChildLayerRenderers = null;
		_scrolledPoint = null;
		rootElementRenderer = null;
		graphicsContext = null;
	}
	
	/////////////////////////////////
	// PUBLIC METHOD
	////////////////////////////////
	
	/**
	 * Called by the document when the graphics
	 * context tree needs to be updated. It
	 * can for instance happen when
	 * a layer which didn't have its own
	 * graphic context should now have it
	 */
	public function updateGraphicsContext(force:Bool):Void
	{
		if (_needsGraphicsContextUpdate == true || force == true)
		{
			_needsGraphicsContextUpdate = false;
			
			if (graphicsContext == null)
			{
				attach();
				return;
			}
			else if (hasOwnGraphicsContext != establishesNewGraphicsContext())
			{
				detach();
				attach();
				return;
			}
		}
		
		var length:Int = childNodes.length;
		for (i in 0...length)
		{
			childNodes[i].updateGraphicsContext(force);
		}
		
	}
	
	/////////////////////////////////
	// PUBLIC INVALIDATION METHOD
	////////////////////////////////
	
	/**
	 * Schedule an update of the graphics context
	 * tree using the document
	 * 
	 * @param force wether the whole graphics context tree
	 * should be updated. Happens when inserting/removing
	 * a compositing layer
	 */
	public function invalidateGraphicsContext(force:Bool):Void
	{
		_needsGraphicsContextUpdate = true;
		var htmlDocument:HTMLDocument = cast(rootElementRenderer.domNode.ownerDocument);
		htmlDocument.invalidateGraphicsContextTree(force);
	}
	
	/**
	 * Invalidate the rendering of this layer.
	 * If this layer has its own graphic context,
	 * each child layer using the same graphics
	 * context is also invalidated
	 */
	public function invalidateRendering():Void
	{
		_needsRendering = true;
		
		//if has own graphic context,
		//invalidate all children with
		//same graphic context
		if (hasOwnGraphicsContext == true)
		{
			var length:Int = childNodes.length;
			for (i in 0...length)
			{
				var child:LayerRenderer = childNodes[i];
				if (child.hasOwnGraphicsContext == false)
				{
					invalidateChildLayerRenderer(child);
				}
				
			}
		}
	}
	
	/////////////////////////////////
	// PRIVATE INVALIDATION METHOD
	////////////////////////////////
	
	/**
	 * Invalidate all children with
	 * the same graphic context as 
	 * this one
	 */
	private function invalidateChildLayerRenderer(rootLayer:LayerRenderer):Void
	{
		rootLayer.invalidateRendering();
		var childNodes:Array<LayerRenderer> = rootLayer.childNodes;
		var length:Int = childNodes.length;
		for (i in 0...length)
		{
			var child:LayerRenderer = childNodes[i];
			if (child.hasOwnGraphicsContext == false)
			{
				invalidateChildLayerRenderer(child);
			}
		}
	}
	
	/////////////////////////////////
	// OVERRIDEN PUBLIC METHODS
	////////////////////////////////
	
	/**
	 * Overriden as when a child LayerRenderer is added
	 * to this LayerRenderer, this LayerRenderer stores its
	 * child LayerRenderer or its root ElementRenderer in one of its child element
	 * renderer array based on its z-index style
	 * 
	 * If the LayerRenderer doesn't establish a new stacking context, the
	 * new child is instead added to its parent, so that the LayerRenderer
	 * tree can reflect the stacking context structure
	 */ 
	override public function appendChild(newChild:LayerRenderer):LayerRenderer
	{
		//add to parent as this LayerRenderer do'esnt establish
		//new stacking context
		if (establishesNewStackingContext() == false)
		{
			return parentNode.appendChild(newChild);
		}
		
		super.appendChild(newChild);
		
		//check the computed z-index of the ElementRenderer which
		//instantiated the child LayerRenderer
		switch(newChild.rootElementRenderer.coreStyle.zIndex)
		{
			case KEYWORD(value):
				if (value != AUTO)
				{
					throw 'Illegal value for z-index style';
				}
				//the z-index is 'auto'
				_zeroAndAutoZIndexChildLayerRenderers.push(newChild);
				
			case INTEGER(value):
				if (value == 0)
				{
					_zeroAndAutoZIndexChildLayerRenderers.push(newChild);
				}
				else if (value > 0)
				{
					insertPositiveZIndexChildRenderer(newChild, value);
				}
				else if (value < 0)
				{
					insertNegativeZIndexChildRenderer(newChild, value);
				}
				
			default:
				throw 'Illegal value for z-index style';
		}
		
		//needs to update graphic context, in case the new child
		//changes it
		//
		//TODO 3 : eventually, it might not be needed to invalidate
		//every time
		newChild.invalidateGraphicsContext(newChild.isCompositingLayer());
		
		return newChild;
	}
	
	/**
	 * When removing a child LayerRenderer from the LayerRenderer
	 * tree, its reference must also be removed from the right
	 * child LayerRenderer array
	 */
	override public function removeChild(oldChild:LayerRenderer):LayerRenderer
	{
		
		oldChild.detach();
		//need to update graphic context after removing a child
		//as it might trigger graphic contex creation/deletion
		oldChild.invalidateGraphicsContext(oldChild.isCompositingLayer());
		
		//the layerRenderer was added to the parent as this
		//layerRenderer doesn't establish a stacking context
		if (establishesNewStackingContext() == false)
		{
			return parentNode.removeChild(oldChild);
		}
		
		var removed:Bool = false;
		
		//try each of the array, stop if an element was actually removed from them
		removed = _zeroAndAutoZIndexChildLayerRenderers.remove(oldChild);
		
		if (removed == false)
		{
			removed = _positiveZIndexChildLayerRenderers.remove(oldChild);
			
			if (removed == false)
			{
				 _negativeZIndexChildLayerRenderers.remove(oldChild);
			}
		}
		
		super.removeChild(oldChild);
		
		return oldChild;
	}
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// PUBLIC ATTACHEMENT METHODS
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * For a LayerRenderer, attach is used to 
	 * get a reference to a GraphicsContext to
	 * paint onto
	 */
	public function attach():Void
	{
		attachGraphicsContext();
		
		//attach all its children recursively
		var length:Int = childNodes.length;
		for (i in 0...length)
		{
			var child:LayerRenderer = childNodes[i];
			child.attach();
		}
	}
	
	/**
	 * For a LayerRenderer, detach is used
	 * to dereference the GraphicsContext
	 */
	public function detach():Void
	{
		var length:Int = childNodes.length;
		for (i in 0...length)
		{
			var child:LayerRenderer = childNodes[i];
			child.detach();
		}
		
		detachGraphicsContext();
	}
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// PRIVATE ATTACHEMENT METHODS
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * Attach a graphics context if necessary
	 */
	private function attachGraphicsContext():Void
	{
		if (parentNode != null)
		{
			createGraphicsContext(parentNode.graphicsContext);
		}
	}
	
	/**
	 * Detach the GraphicContext
	 */
	private function detachGraphicsContext():Void 
	{
		//if this LayerRenderer instantiated its own
		//GraphicContext, it is responsible for disposing of it
		if (hasOwnGraphicsContext == true)
		{
			parentNode.graphicsContext.removeChild(graphicsContext);
			graphicsContext.dispose();
			hasOwnGraphicsContext = false;
		}
		
		graphicsContext = null;
	}
	
	/**
	 * Create a new GraphicsContext for this LayerRenderer
	 * or use the one of its parent
	 */
	private function createGraphicsContext(parentGraphicsContext:GraphicsContext):Void
	{
		if (establishesNewGraphicsContext() == true)
		{
			graphicsContext = new GraphicsContext(this);
			_needsBitmapSizeUpdate = true;
			hasOwnGraphicsContext = true;
			parentGraphicsContext.appendChild(graphicsContext);
		}
		else
		{
			graphicsContext = parentGraphicsContext;
		}
	}
	
	/**
	 * Wether this LayerRenderer should create its
	 * own GraphicsContext
	 */
	private function establishesNewGraphicsContext():Bool
	{
		if (hasCompositingLayerDescendant(this) == true)
		{
			return true;
		}
		else if (hasCompositingLayerSibling() == true)
		{
			return true;
		}
		
		return false;
	}
	
	/**
	 * Return wether a given layer has a descendant which is
	 * a compositing layer by traversing the layer tree
	 * recursively.
	 * 
	 * If it does, it must then have its own graphic context
	 * to respect z-index when compositing
	 */
	private function hasCompositingLayerDescendant(rootLayerRenderer:LayerRenderer):Bool
	{
		var layerLength:Int = rootLayerRenderer.childNodes.length;
		for (i in 0...layerLength)
		{
			var childLayer:LayerRenderer = rootLayerRenderer.childNodes[i];
			if (childLayer.isCompositingLayer() == true)
			{
				return true;
			}
			else if (childLayer.hasChildNodes() == true)
			{
				var hasCompositingLayer:Bool = hasCompositingLayerDescendant(childLayer);
				if (hasCompositingLayer == true)
				{
					return true;
				}
			}
		}
		
		return false;
	}
	
	/**
	 * return wether this layer has a sibling which
	 * is a compositing layer which has a lower z-index
	 * than itself.
	 * 
	 * If the layer has such a sibling, it means it is
	 * composited on top of a compositing layer and
	 * it must have its own graphic context to respect
	 * z-index
	 */
	private function hasCompositingLayerSibling():Bool
	{
		//get all the sibling by retrieving parent node
		var parentChildNodes:Array<LayerRenderer> = parentNode.childNodes;
		
		for (i in 0...parentChildNodes.length)
		{
			var child:LayerRenderer = parentChildNodes[i];
			if (child != this)
			{
				if (child.isCompositingLayer() == true)
				{
					return hasLowerZIndex(child);
				}
			}
		}
		
		return false;
	}
	
	/**
	 * Return wether a sibling layer has
	 * a lower z-index than this layer
	 * 
	 * TODO 1 : implement
	 */
	private function hasLowerZIndex(siblingLayer:LayerRenderer):Bool
	{
		return true;
	}
	
	/////////////////////////////////
	// PUBLIC HELPER METHODS
	////////////////////////////////
	
	/**
	 * Wether this layer is a compositing layer,
	 * meaning it always have its own graphic context.
	 * For instance, a GPU accelerated video layer is always a
	 * compositing layer
	 */
	public function isCompositingLayer():Bool
	{
		return false;
	}
	
	/////////////////////////////////
	// PUBLIC RENDERING METHODS
	////////////////////////////////
	
	/**
	 * Starts the rendering of this LayerRenderer.
	 * Render all its child layers and its root ElementRenderer
	 * 
	 * @param windowWidth the current width of the window
	 * @param windowHeight the current height of the window
	 */
	public function render(windowWidth:Int, windowHeight:Int ):Void
	{
		//if the graphic context was instantiated/re-instantiated
		//since last rendering, the size of its bitmap data should be
		//updated with the viewport's dimensions
		if (_needsBitmapSizeUpdate == true)
		{
			if (hasOwnGraphicsContext == true)
			{
				graphicsContext.initBitmapData(windowWidth, windowHeight);
			}
			_needsBitmapSizeUpdate = false;
			
			//invalidate rendering of this layer and all layers sharing
			//the same graphic context
			invalidateRendering();
		}
		//else update the dimension of the bitmap data if the window size changed
		//since last rendering
		else if (windowWidth != _windowWidth || windowHeight != _windowHeight)
		{
			//only update the GraphicContext if it was created
			//by this LayerRenderer
			if (hasOwnGraphicsContext == true)
			{
				graphicsContext.initBitmapData(windowWidth, windowHeight);
				_needsBitmapSizeUpdate = false;
			}
			
			//invalidate if the size of the viewport
			//changed
			invalidateRendering();
		}
		
		_windowWidth = windowWidth;
		_windowHeight = windowHeight;
	
		//only clear if a rendering is necessary
		if (_needsRendering == true)
		{
			//only clear the bitmaps if the GraphicsContext
			//was created by this LayerRenderer
			if (hasOwnGraphicsContext == true)
			{
				//reset the bitmap
				graphicsContext.clear();
			}
		}
	
		//init transparency on the graphicContext if the element is transparent. Everything
		//painted afterwards will have an alpha equal to the opacity style
		//
		//TODO 1 : will not work if child layer also have alpha, alpha
		//won't be combined properly. Should GraphicsContext have offscreen bitmap
		//for each transparent layer and compose them when transparency end ?
		if (rootElementRenderer.isTransparent() == true)
		{
			var coreStyle:CoreStyle = rootElementRenderer.coreStyle;
			
			//get the current opacity value
			var opacity:Float = 0.0;
			switch(coreStyle.opacity)
			{
				case NUMBER(value):
					opacity = value;
					
				case ABSOLUTE_LENGTH(value):
					opacity = value;
					
				default:	
			}
			
			graphicsContext.beginTransparency(opacity);
		}
		
		//render first negative z-index child LayerRenderer from most
		//negative to least negative
		var negativeChildLength:Int = _negativeZIndexChildLayerRenderers.length;
		for (i in 0...negativeChildLength)
		{
			_negativeZIndexChildLayerRenderers[i].render(windowWidth, windowHeight);
		}
		
		//only render if necessary. This only applies to layer which have
		//their own graphic context, layer which don't always gets re-painted
		//
		//TODO 2 : invalidation for layer is still messy
		if (_needsRendering == true || hasOwnGraphicsContext == false)
		{
			//render the rootElementRenderer itself which will also
			//render all ElementRenderer belonging to this LayerRenderer
			rootElementRenderer.render(graphicsContext);
		}
		
		//render zero and auto z-index child LayerRenderer, in tree order
		var childLength:Int = _zeroAndAutoZIndexChildLayerRenderers.length;
		for (i in 0...childLength)
		{
			_zeroAndAutoZIndexChildLayerRenderers[i].render(windowWidth, windowHeight);
		}
		
		//render all the positive LayerRenderer from least positive to 
		//most positive
		var positiveChildLength:Int = _positiveZIndexChildLayerRenderers.length;
		for (i in 0...positiveChildLength)
		{
			_positiveZIndexChildLayerRenderers[i].render(windowWidth, windowHeight);
		}
		
		//stop transparency so that subsequent painted element won't be transparent
		//if they don't themselves have an opacity inferior to 1
		if (rootElementRenderer.isTransparent() == true)
		{
			graphicsContext.endTransparency();
		}
		
		//scrollbars are always rendered last as they should always be the top
		//element of their layer
		rootElementRenderer.renderScrollBars(graphicsContext, windowWidth, windowHeight);
		
		//only render if necessary
		if (_needsRendering == true || hasOwnGraphicsContext)
		{
			//apply transformations to the layer if needed
			if (rootElementRenderer.isTransformed() == true)
			{
				//TODO 2 : should already be computed at this point
				VisualEffectStylesComputer.compute(rootElementRenderer.coreStyle);
				graphicsContext.transform(getTransformationMatrix(graphicsContext));
			}
		}
		
		//layer no longer needs rendering
		_needsRendering = false;
	}
	
	/////////////////////////////////
	// PRIVATE RENDERING METHODS
	////////////////////////////////
	
	/**
	 * Compute all the transformation that should be applied to this LayerRenderer
	 * and return it as a transformation matrix
	 */
	private function getTransformationMatrix(graphicContext:GraphicsContext):Matrix
	{
		var relativeOffset:PointVO = rootElementRenderer.getRelativeOffset();
		var concatenatedMatrix:Matrix = getConcatenatedMatrix(rootElementRenderer.coreStyle.usedValues.transform, relativeOffset);
		
		//apply relative positioning as well
		concatenatedMatrix.translate(relativeOffset.x, relativeOffset.y);
		
		return concatenatedMatrix;
	}
	
	/**
	 * Concatenate the transformation matrix obtained with the
	 * transform and transform-origin styles with the current
	 * transformations applied to the root element renderer, such as for 
	 * instance its position in the global space
	 */
	private function getConcatenatedMatrix(matrix:Matrix, relativeOffset:PointVO):Matrix
	{
		var currentMatrix:Matrix = new Matrix();
		var globalBounds:RectangleVO = rootElementRenderer.globalBounds;
		
		//translate to the coordinate system of the root element renderer
		currentMatrix.translate(globalBounds.x + relativeOffset.x, globalBounds.y + relativeOffset.y);
		
		currentMatrix.concatenate(matrix);
		
		//translate back from the coordinate system of the root element renderer
		currentMatrix.translate((globalBounds.x + relativeOffset.x) * -1, (globalBounds.y + relativeOffset.y) * -1);
		return currentMatrix;
	}
	
	/////////////////////////////////
	// PRIVATE LAYER TREE METHODS
	////////////////////////////////
	
	/**
	 * When inserting a new child LayerRenderer in the positive z-index
	 * child LayerRenderer array, it must be inserted at the right index so that
	 * the array is ordered from least positive to most positive
	 */
	private function insertPositiveZIndexChildRenderer(childLayerRenderer:LayerRenderer, rootElementRendererZIndex:Int):Void
	{
		//flag checking if the LayerRenderer was already inserted
		//in the array
		var isInserted:Bool = false;
		
		//loop in all the positive z-index array
		var length:Int = _positiveZIndexChildLayerRenderers.length;
		for (i in 0...length)
		{
			//get the z-index of the child LayerRenderer at the current index
			var currentRendererZIndex:Int = 0;
			switch(_positiveZIndexChildLayerRenderers[i].rootElementRenderer.coreStyle.zIndex)
			{
				case INTEGER(value):
					currentRendererZIndex = value;
					
				default:	
			}
			
			//if the new LayerRenderer has a least positive z-index than the current
			//child it is inserted at this index
			if (rootElementRendererZIndex < currentRendererZIndex)
			{
				_positiveZIndexChildLayerRenderers.insert(i, childLayerRenderer);
				isInserted = true;
				break;
			}
		}
		
		//if the new LayerRenderer wasn't inserted, either
		//it is the first item in the array or it has the most positive
		//z-index
		if (isInserted == false)
		{
			_positiveZIndexChildLayerRenderers.push(childLayerRenderer);
		}
	}
	
	/**
	 * Follows the same logic as the method above for the negative z-index child
	 * array. The array must be ordered from most negative to least negative
	 */ 
	private function insertNegativeZIndexChildRenderer(childLayerRenderer:LayerRenderer, rootElementRendererZIndex:Int):Void
	{
		var isInserted:Bool = false;
		
		var length:Int = _negativeZIndexChildLayerRenderers.length;
		for (i in 0...length)
		{
			var currentRendererZIndex:Int = 0;
			
			switch(_negativeZIndexChildLayerRenderers[i].rootElementRenderer.coreStyle.zIndex)
			{
				case INTEGER(value):
					currentRendererZIndex = value;
					
				default:	
			}
			
			if (currentRendererZIndex  > rootElementRendererZIndex)
			{
				_negativeZIndexChildLayerRenderers.insert(i, childLayerRenderer);
				isInserted = true;
				break;
			}
		}
		
		if (isInserted == false)
		{
			_negativeZIndexChildLayerRenderers.push(childLayerRenderer);
		}
	}
	
	/**
	 * Wether this LayerRenderer establishes a new stacking
	 * context. If it does it is responsible for rendering
	 * all the LayerRenderer in the same stacking context, 
	 * and its child LayerRenderer which establish new
	 * stacking context themselves
	 */
	private function establishesNewStackingContext():Bool
	{
		switch(rootElementRenderer.coreStyle.zIndex)
		{
			case KEYWORD(value):
				if (value == AUTO)
				{
					return false;
				}
				
			default:	
		}
		
		return true;
	}

	/////////////////////////////////
	// PUBLIC HIT-TESTING METHODS
	////////////////////////////////
	
	//TODO 2 : for now traverse all tree, but should instead return as soon as an ElementRenderer
	//is found
	/**
	 * For a given point return the top most ElementRenderer whose bounds contain this point. The top
	 * most element is determined by the z-index of the layer renderers. If 2 or more elements matches
	 * the point, the one belonging to the higher layer renderer will be returned
	 * 
	 * TODO 2 : shouldn' the scroll offset be directly added to the point ?
	 * 
	 * @param	point the target point relative to the window
	 * @param	scrollX the x scroll offset applied to the point
	 * @param	scrollY the y scroll offset applied to the point
	 */
	public function getTopMostElementRendererAtPoint(point:PointVO, scrollX:Float, scrollY:Float):ElementRenderer
	{
		//get all the elementRenderers under the point
		var elementRenderersAtPoint:Array<ElementRenderer> = getElementRenderersAtPoint(point, scrollX, scrollY);
		//return the top most, the last of the array
		return elementRenderersAtPoint[elementRenderersAtPoint.length - 1];
	}
	
	/**
	 * Get all the ElemenRenderer whose bounds contain the given point. The returned
	 * ElementRenderer are ordered by z-index, from smallest to biggest.
	 */
	private function getElementRenderersAtPoint(point:PointVO, scrollX:Float, scrollY:Float):Array<ElementRenderer>
	{
		var elementRenderersAtPoint:Array<ElementRenderer> = getElementRenderersAtPointInLayer(rootElementRenderer, point, scrollX, scrollY);

		if (rootElementRenderer.hasChildNodes() == true)
		{
			var childRenderers:Array<ElementRenderer> = getChildRenderers();
			
			var elementRenderersAtPointInChildRenderers:Array<ElementRenderer> = getElementRenderersAtPointInChildRenderers(point, childRenderers, scrollX, scrollY);
			var length:Int = elementRenderersAtPointInChildRenderers.length;
			for (i in 0...length)
			{
				elementRenderersAtPoint.push(elementRenderersAtPointInChildRenderers[i]);
			}
		}
	
		return elementRenderersAtPoint;
	}
	
	/////////////////////////////////
	// PRIVATE HIT-TESTING METHODS
	////////////////////////////////
	
	/**
	 * For a given layer, return all of the ElementRenderer belonging to this
	 * layer whose bounds contain the target point.
	 * 
	 * The rendering tree is traversed recursively, starting from the
	 * root element renderer of this layer
	 * 
	 * TODO 2 : can probably be optimised, in one layer, no elements are supposed to
	 * overlap, meaning that only 1 elementRenderer can be returned for each layer
	 */
	private function getElementRenderersAtPointInLayer(renderer:ElementRenderer, point:PointVO, scrollX:Float, scrollY:Float):Array<ElementRenderer>
	{
		var elementRenderersAtPointInLayer:Array<ElementRenderer> = new Array<ElementRenderer>();
		
		_scrolledPoint.x = point.x + scrollX;
		_scrolledPoint.y = point.y + scrollY;
		
		//if the target point is within the ElementRenderer bounds, store
		//the ElementRenderer
		if (isWithinBounds(_scrolledPoint, renderer.globalBounds) == true)
		{
			//ElementRenderer which are no currently visible
			//can't be hit
			if (renderer.isVisible() == true)
			{
				elementRenderersAtPointInLayer.push(renderer);
			}
		}
		
		scrollX += renderer.scrollLeft;
		scrollY += renderer.scrollTop;
		
		var length:Int = renderer.childNodes.length;
		//loop in all the ElementRenderer using this LayerRenderer
		for (i in 0...length)
		{
			var child:ElementRenderer = renderer.childNodes[i];
			
			if (child.layerRenderer == this)
			{
				if (child.hasChildNodes() == true)
				{
					var childElementRenderersAtPointInLayer:Array<ElementRenderer> = getElementRenderersAtPointInLayer(child, point, scrollX, scrollY);
					var childLength:Int = childElementRenderersAtPointInLayer.length;
					for (j in 0...childLength)
					{
						if (childElementRenderersAtPointInLayer[j].isVisible() == true)
						{
							elementRenderersAtPointInLayer.push(childElementRenderersAtPointInLayer[j]);
						}
					}
				}
				else
				{
					_scrolledPoint.x = point.x + scrollX;
					_scrolledPoint.y = point.y + scrollY;
					
					if (isWithinBounds(_scrolledPoint, child.globalBounds) == true)
					{
						if (child.isVisible() == true)
						{
							elementRenderersAtPointInLayer.push(child);
						}
					}
				}
			}
		}
		
		return elementRenderersAtPointInLayer;
	}
	
	private function getElementRenderersAtPointInChildRenderers(point:PointVO, childRenderers:Array<ElementRenderer>, scrollX:Float, scrollY:Float):Array<ElementRenderer>
	{
		var elementRenderersAtPointInChildRenderers:Array<ElementRenderer> = new Array<ElementRenderer>();
		
		var length:Int = childRenderers.length;
		for (i in 0...length)
		{
			
			var elementRenderersAtPointInChildRenderer:Array<ElementRenderer> = [];
			if (childRenderers[i].createOwnLayer() == true)
			{
				//TODO 1 : messy, ElementRenderer should be aware of their scrollBounds
				if (childRenderers[i].isScrollBar() == true)
				{
					elementRenderersAtPointInChildRenderer = childRenderers[i].layerRenderer.getElementRenderersAtPoint(point, scrollX, scrollY);
				}
				//TODO 1 : messy, ElementRenderer should be aware of their scrollBounds
				else if (childRenderers[i].coreStyle.getKeyword(childRenderers[i].coreStyle.position) == FIXED)
				{
					elementRenderersAtPointInChildRenderer = childRenderers[i].layerRenderer.getElementRenderersAtPoint(point, scrollX , scrollY);
				}
				else
				{
					elementRenderersAtPointInChildRenderer = childRenderers[i].layerRenderer.getElementRenderersAtPoint(point, scrollX + rootElementRenderer.scrollLeft, scrollY + rootElementRenderer.scrollTop);
				}
			}
		
			var childLength:Int = elementRenderersAtPointInChildRenderer.length;
			for (j in 0...childLength)
			{
				elementRenderersAtPointInChildRenderers.push(elementRenderersAtPointInChildRenderer[j]);
			}
		}
		
		
		return elementRenderersAtPointInChildRenderers;
	}
	
	/**
	 * Utils method determining if a given point is within
	 * a given recrtangle
	 */
	private function isWithinBounds(point:PointVO, bounds:RectangleVO):Bool
	{
		return point.x >= bounds.x && (point.x <= bounds.x + bounds.width) && point.y >= bounds.y && (point.y <= bounds.y + bounds.height);	
	}
	
	/**
	 * Concatenate all the child element renderers of this
	 * LayerRenderer
	 */
	private function getChildRenderers():Array<ElementRenderer>
	{
		var childRenderers:Array<ElementRenderer> = new Array<ElementRenderer>();
		
		for (i in 0..._negativeZIndexChildLayerRenderers.length)
		{
			var childRenderer:LayerRenderer = _negativeZIndexChildLayerRenderers[i];
			childRenderers.push(childRenderer.rootElementRenderer);
		}
		for (i in 0..._zeroAndAutoZIndexChildLayerRenderers.length)
		{
			var childRenderer:LayerRenderer = _zeroAndAutoZIndexChildLayerRenderers[i];
			childRenderers.push(childRenderer.rootElementRenderer);
		}
		for (i in 0..._positiveZIndexChildLayerRenderers.length)
		{
			var childRenderer:LayerRenderer = _positiveZIndexChildLayerRenderers[i];
			childRenderers.push(childRenderer.rootElementRenderer);
		}
		
		return childRenderers;
	}
}