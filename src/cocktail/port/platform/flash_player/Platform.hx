/*
	This file is part of Cocktail http://www.silexlabs.org/groups/labs/cocktail/
	This project is © 2010-2011 Silex Labs and is released under the GPL License:
	This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License (GPL) as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version. 
	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	To read the license please visit http://www.gnu.org/copyleft/gpl.html
*/
package cocktail.port.platform.flash_player;

import cocktail.Config;
import cocktail.core.event.Event;
import cocktail.core.event.EventConstants;
import cocktail.core.event.UIEvent;
import cocktail.core.html.HTMLConstants;
import cocktail.core.html.HTMLElement;
import cocktail.core.layer.LayerRenderer;
import cocktail.core.stacking.StackingContext;
import cocktail.core.geom.GeomData;
import cocktail.port.base.PlatformBase;
import cocktail.port.NativeBitmapData;
import cocktail.port.NativeElement;
import cocktail.port.NativeLayer;
import flash.display.Bitmap;
import flash.display.Sprite;
import flash.display.StageDisplayState;
import flash.display.StageQuality;
import flash.Lib;
import flash.net.URLRequest;
import haxe.Log;

/**
 * This is the flash AVM2 implementation of the native platform.
 * Listens to flash global events, such as Stage resize and exposes
 * some flash public API
 * 
 * @author Yannick DOMINGUEZ
 */
class Platform extends PlatformBase
{
	/**
	 * The name of the attribute whose value to lookup on the flash Stage
	 * to determine wether fullscreen mode is allowed
	 */
	private static inline var ALLOW_FULLSCREEN_ATTRIBUTE:String = "allowsFullScreen";
	
	/**
	 * The Sprite that will be used as a root for the document,
	 * is directly attached to flash Stage
	 */
	private var _rootSprite:Sprite;
	
	/**
	 * The Sprite used as root for the native layers
	 * of the document
	 */
	private var _nativeLayersRootSprite:Sprite;
	
	/**
	 * The sprite used for hit testint, e.g listening
	 * for mouse and touch event coming from the flash
	 * player. 
	 * 
	 * It must always be on top of all the native layer 
	 * tree, as if external swf are loaded, they might
	 * otherwise interfer with hit testing
	 * 
	 * Set public so that mouse and touch listener classes
	 * can access it
	 */
	public var hitTestingSprite:Sprite;
	
	/**
	 * During update of hit testing Sprite, hold a ref
	 * to the bounds of layer created by object tag, so
	 * that they can be used to create "hole" in the hit
	 * testing Sprite, so that swf movie can be interacted
	 * with
	 */
	private var _objectTagsBounds:Array<RectangleVO>;
	
	/**
	 * During update of hit testing Sprite, set to true
	 * as soon as one layer created by an "object" tag
	 * is found
	 */
	private var _foundObjectTag:Bool;
	
	/**
	 * class constructor
	 */
	public function new() 
	{
		initDisplayList();
		
		super();
		
		//in Flash, the Stage is always defined as no scale as the transformations
		//will be managed by Cocktail
		flash.Lib.current.stage.scaleMode = flash.display.StageScaleMode.NO_SCALE;
		
		//optionnally may display with low quality
		//to improve rendering speed.
		if (Config.USE_LOW_STAGE_QUALITY == true)
		{
			Lib.current.stage.quality = StageQuality.LOW;
		}
	}
	
	/**
	 * Init the flash display list used
	 * for cocktail document
	 */
	private function initDisplayList():Void
	{
		_rootSprite = new Sprite();
		
		_nativeLayersRootSprite = new Sprite();
		_rootSprite.addChild(_nativeLayersRootSprite);
		
		hitTestingSprite = new Sprite();
		updateHitTestingSprite();
		_rootSprite.addChild(hitTestingSprite);
		
		Lib.current.addChild(_rootSprite);
	}
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// OVERRIDEN PUBLIC METHOD
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * Open a new window using flash API
	 */
	override public function open(url:String, name:String):Void
	{
		flash.Lib.getURL(new URLRequest(url), name);
	}
		
	/**
	 * Uses flash fullscreen API
	 */
	override public function enterFullscreen():Void
	{
		flash.Lib.current.stage.displayState = StageDisplayState.FULL_SCREEN;
	}
	
	/**
	 * Uses flash fullscreen API
	 */
	override public function exitFullscreen():Void
	{
		flash.Lib.current.stage.displayState = StageDisplayState.NORMAL;
	}
	
	/**
	 * Look for the allowFullScreen attribute on the Stage
	 * to determine wether fullscreen is allowed.
	 * A bit hackish but no other way in flash
	 */
	override public function fullScreenEnabled():Bool
	{
		return Reflect.hasField(Lib.current.stage, ALLOW_FULLSCREEN_ATTRIBUTE);
	}
	
	/**
	 * uses flash fullscreen API
	 */
	override public function fullscreen():Bool
	{
		return flash.Lib.current.stage.displayState == StageDisplayState.FULL_SCREEN;
	}
	
	/**
	 * Return the flash Stage
	 */
	override public function getInitialNativeLayer():NativeLayer
	{
		return _nativeLayersRootSprite;
	}
	
	/**
	 * Update the hit testing Sprite in flash, so that it covers the bounds
	 * of all the layer in the document except the layer created by 
	 * object elements.
	 * 
	 * Note : this solution is a workaround for the fact that if there is an
	 * object tag which load a swf movie in the document, the swf movie will prevent
	 * hit testing from working properly in cocktail. This is only an issue when there
	 * is html elements generated by cocktail on top of the swf content.
	 * 
	 * For instance if there is a swf movie on the stage, if the hit testing Sprite is
	 * below it, then the swf movie will prevent cocktail from receiving mouse and
	 * touch event. If instead the hit testing Sprite is above the swf, then the swf
	 * won't receive mouse and touch event
	 * 
	 * One solution which almost worked was to simulate event dispatching on the loaded
	 * swf, but some swf, like Youtube API prevent accessing the inner display list
	 * 
	 * The "best" solution found, is to draw on the hit testing sprite all the region
	 * which corresponds to layers which are not created by "object" elements
	 */
	override public function updateHitTestingBounds(stackingContext:StackingContext):Void
	{
		_objectTagsBounds = new Array<RectangleVO>();
		_foundObjectTag = false;
		
		updateHitTestingSprite();
		doUpdateHitTestingBounds(stackingContext);
	}
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// Overriden private utils methods
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * Set resize listeners on the stage
	 */
	override private function setNativeListeners():Void
	{
		Lib.current.stage.addEventListener(flash.events.Event.RESIZE, onNativeResize);
		
		//not supported by nme
		#if flash9
		Lib.current.stage.addEventListener(flash.events.FullScreenEvent.FULL_SCREEN, onNativeFullScreenChange);
		#end
	}
	
	/**
	 * Remove resize listeners from the stage
	 */
	override private function removeNativeListeners():Void
	{
		Lib.current.stage.removeEventListener(flash.events.Event.RESIZE, onNativeResize);
		
		//not supported by nme
		#if flash9
		Lib.current.stage.removeEventListener(flash.events.FullScreenEvent.FULL_SCREEN, onNativeFullScreenChange);
		#end
	}
	
	/**
	 * Create and return a cross-platform resize event
	 * from the flash event
	 * 
	 * @param	event the native event
	 */
	override private function getUIEvent(event:Dynamic):UIEvent
	{
		var resizeEvent:UIEvent = new UIEvent();
		resizeEvent.initUIEvent(EventConstants.RESIZE, false, false, null, 0.0);
		
		return resizeEvent;
	}
	
	/**
	 * Create and return a cross-platform event
	 * from the dispatched native event
	 * 
	 * @param	event the native event
	 */
	override private function getEvent(event:Dynamic):Event
	{
		var fullScreenChangeEvent:Event = new Event();
		fullScreenChangeEvent.initEvent(EventConstants.FULL_SCREEN_CHANGE, false, false);
		
		return fullScreenChangeEvent;
	}
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// Overriden events method
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * When the Stage is resize, the hit testing
	 * sprite must be updated
	 */
	override private function onNativeResize(event:Dynamic):Void
	{
		updateHitTestingSprite();
		super.onNativeResize(event);
	}
	
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// Private utils method
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * draw/redraw the background of the 
	 * hit testing Sprite, which must
	 * match the size of the Stage
	 */
	private function updateHitTestingSprite():Void
	{
		hitTestingSprite.graphics.clear();
		hitTestingSprite.graphics.beginFill(0x000000, 0);
		hitTestingSprite.graphics.drawRect(0, 0, innerWidth, innerHeight);
		hitTestingSprite.graphics.endFill();
	}
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// Overriden GETTER/SETTER
	//////////////////////////////////////////////////////////////////////////////////////////
	
	/**
	 * Return the flash Stage height
	 */
	override private function get_innerHeight():Int
	{
		return Lib.current.stage.stageHeight;
	}
	
	/**
	 * Return the flash Stage width
	 */
	override private function get_innerWidth():Int
	{
		return Lib.current.stage.stageWidth;
	}
	
	
	//////////////////////////////////////////////////////////////////////////////////////////
	// PRIVATE METHODS
	//////////////////////////////////////////////////////////////////////////////////////////

	/**
	 * Called when a layer created by an "object" element
	 * is found, reset the hit testing Sprite by filling
	 * its surface then create hole for each object layer
	 * found so far
	 */
	private function resetHitTestingSprite():Void
	{
		hitTestingSprite.graphics.clear();
		hitTestingSprite.graphics.beginFill(0xFF0000, 0.5);
		hitTestingSprite.graphics.drawRect(0, 0, innerWidth, innerHeight);
		
		
		for (i in 0..._objectTagsBounds.length)
		{
			hitTestingSprite.graphics.drawRect(_objectTagsBounds[i].x,
			_objectTagsBounds[i].y, _objectTagsBounds[i].width, _objectTagsBounds[i].height);
		}
		
		hitTestingSprite.graphics.endFill();
	}
	
	/**
	 * Called when a layer which is not created by an object tag is found,
	 * fill the hit testing Sprite withits bound, so that the layer can be clicked
	 */
	private function fillHitTestingSprite(rect:RectangleVO):Void
	{
		hitTestingSprite.graphics.beginFill(0xFF0000, 0.5);
		hitTestingSprite.graphics.drawRect(rect.x, rect.y, rect.width, rect.height);
		hitTestingSprite.graphics.endFill();
	}
	
	/**
	 * Check wether a layer was created with an object element
	 * If it does, create hole in hit testing Sprite for those
	 * else fill the hit testing Sprite with the bounds of the layer
	 */
	private function hitTestLayer(layerRenderer:LayerRenderer):Void
	{
		if (layerRenderer.rootElementRenderer.domNode.tagName == HTMLConstants.HTML_OBJECT_TAG_NAME)
		{
			_foundObjectTag = true;
			_objectTagsBounds.push(layerRenderer.bounds);
			resetHitTestingSprite();
		}
		else
		{
			if (_foundObjectTag == true)
			{
				fillHitTestingSprite(layerRenderer.bounds);
			}
		}
	}
	
	/**
	 * Traverse the stacking context tree recursively,
	 * in z-index order and fill the hit testing Sprite
	 * accordingly.
	 * 
	 * Logic is similar to rendering of stacking context
	 */
	public function doUpdateHitTestingBounds(stackingContext:StackingContext):Void
	{
		hitTestLayer(stackingContext.layerRenderer);
		
		var child:StackingContext = stackingContext.firstChild;
		
		var hasHitTestedAutoAndZeroLayers:Bool = false;
		
		while (child != null)
		{
			switch(child.layerRenderer.rootElementRenderer.coreStyle.zIndex)
			{
				case INTEGER(value):
					
					if (value == 0)
					{
						
					}
					else
					{
						if (value > 0 && hasHitTestedAutoAndZeroLayers == false)
						{
							hitTestChildrenInSameStackingContext(stackingContext.layerRenderer);
							hasHitTestedAutoAndZeroLayers = true;
						}
						
						doUpdateHitTestingBounds(child);
					}
					
				default:	
			}
			
			child = child.nextSibling;
		}
		
		if (hasHitTestedAutoAndZeroLayers == false)
		{
			hitTestChildrenInSameStackingContext(stackingContext.layerRenderer);
		}
	}
	
	
	/**
	 * hit test layer 
	 */
	private function hitTestChildrenInSameStackingContext(rootLayer:LayerRenderer):Void
	{
		var child:LayerRenderer = rootLayer.firstChild;
		while (child != null)
		{
			if (child.hasOwnStackingContext == false)
			{
				hitTestLayer(child);
				hitTestChildrenInSameStackingContext(child);
			}
			else
			{
				switch(child.rootElementRenderer.coreStyle.zIndex)
				{
					case INTEGER(value):
						if (value == 0)
						{
							doUpdateHitTestingBounds(child.stackingContext);
						}
					default:	
				}
			}
			
			child = child.nextSibling;
		}
	}
}