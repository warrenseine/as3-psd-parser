package com.durej.PSDParser 
{
	import flash.geom.Point;
	import flash.display.BitmapData;
	import flash.filters.GlowFilter;
	import flash.filters.DropShadowFilter;
	import flash.display.BlendMode;
	import flash.geom.Rectangle;
	import flash.utils.ByteArray;
	/**
	 * @author Slavomir Durej
	 */
	public class PSDLayer 
	{
		public static const LayerType_FOLDER_OPEN 	: String = "folder_open";
		public static const LayerType_FOLDER_CLOSED : String = "folder_closed";
		public static const LayerType_HIDDEN 		: String = "hidden";
		public static const LayerType_NORMAL 		: String = "normal";

		private var fileData				: ByteArray;
		
		public var bmp						: BitmapData;
		public var bounds					: Rectangle;
		public var position					: Point;
		public var name						: String;
		public var type						: String = LayerType_NORMAL;
		public var layerID					: uint;
		public var numChannels				: int;
		public var channelsInfo_arr			: Array;
		public var blendModeKey				: String;
		public var blendMode				: String;
		public var alpha					: Number;
		public var maskBounds				: Rectangle;
		public var maskBounds2				: Rectangle;	
		public var clippingApplied			: Boolean;
		public var isLocked					: Boolean;
		public var isVisible				: Boolean;
		public var pixelDataIrrelevant		: Boolean;
		public var nameUNI					: String; //layer unicode name		
		public var filters_arr				: Array; //filters array	
			
		public function PSDLayer(fileData:ByteArray) 
		{
			this.fileData = fileData;
			readLayerBasicInfo();	
		}
		

		private function readLayerBasicInfo() : void 
		{
			
			//------------------------------------------------------------- get bounds
			/*
			4 * 4 bytes.
			Rectangle containing the contents of the layer. Specified as top, left,
			bottom, right coordinates.
			*/
			bounds 		= readRect();
			position	= new Point(bounds.x, bounds.y);
			
			//------------------------------------------------------------- get num channels
			/*
			2 bytes.
			The number of channels in the layer.
			*/
			numChannels 	= fileData.readUnsignedShort(); //readShortInt
			
			//------------------------------------------------------------- get Layer channel info
			/*
			6 * number of channels bytes
			Channel information. Six bytes per channel.
			*/
			channelsInfo_arr		= new Array( numChannels );
			
			for ( var i:uint = 0; i < numChannels; ++i ) 
			{
				channelsInfo_arr[i] = new PSDChannelInfoVO(fileData);
			}
			
			//------------------------------------------------------------- get signature
			/*
			4 bytes.
			Blend mode signature. 
			*/
			var sig:String = fileData.readUTFBytes( 4 );
			if (sig != "8BIM") throw new Error("Invalid Blend mode signature: " + sig ); 

			//------------------------------------------------------------- get blend mode key
			/*
			4 bytes.
			Blend mode key.
			*/
			blendModeKey = fileData.readUTFBytes( 4 );

			//------------------------------------------------------------- get blend mode
			/*
			matches the flash blend mode to photoshop layer blen mode if match is found
			it the blend modes are not compatible "BlendMode.NORMAL is used" 
			*/
			blendMode = getBlendMode();
			
			//------------------------------------------------------------- get opacity
			/*
			1 byte.
			Opacity. 0 = transparent ... 255 = opaque
			*/
			var opacity:int = fileData.readUnsignedByte();
			
			//converts to more flash friendly alpha
			alpha = opacity/255;
			
			//------------------------------------------------------------- get clipping
			/*
			1 byte.
			Clipping. 0 (false) = base, 1 (true) = non-base
			 */
			clippingApplied = fileData.readBoolean();
			
			
			//------------------------------------------------------------- get flags
			/*
			1 byte.
			bit 0 = transparency protected 
			bit 1 = visible
			bit 2 = obsolete
			bit 3 = 1 for Photoshop 5.0 and later, tells if bit 4 has useful information;
			bit 4 = pixel data irrelevant to appearance of document
			*/
			var flags:uint = fileData.readUnsignedByte();
			
			//transparency protected 
			isLocked = ((flags&1) != 0);
			
			//visible
			isVisible = ((flags&2) == 0);
			
			//irrelevant
			if ((flags&3) != 0) pixelDataIrrelevant = (flags&4) != 0; //543
			
			// padding
			fileData.position += 1; 
			
			//----------------------------------------------------------------------------
			//------------------------------------------------------------- get extra data
			//----------------------------------------------------------------------------
			
			var extraSize	:uint = fileData.readUnsignedInt(); //561
			var pos			:int 	= fileData.position;
			var size		:int;

			//------------------------------------------------------------- get layer mask (564)
			parseLayerMaskData(fileData);
			
			//------------------------------------------------------------- get blending ranges (570)
			//parseLayerBlendingRanges( fileData );
			//skipping for now..
			var layerBlendingRangesSectionSize:uint = fileData.readUnsignedInt();
			fileData.position+=layerBlendingRangesSectionSize;
			
			//------------------------------------------------------------- get layer name (576)
			var nameObj:Object = readPascalStringObj();
			name = nameObj.str;
			
			
			//remember this position
			var prevPos:uint	= fileData.position;
			
			//----------------------------------------------------------------------------------
			//------------------------------------------------------------- read layer info tags
			//----------------------------------------------------------------------------------
			
			while (fileData.position - pos < extraSize) 
			{
				//------------------------------------------------------------- get signature
				sig = fileData.readUTFBytes(4);
				
				//check signature
				if (sig != "8BIM") throw new Error("layer information signature error");
				
				//------------------------------------------------------------- get layer tag
				/*
				4 bytes.
				Key: a 4-character code
				*/
				var tag:String = fileData.readUTFBytes(4); //readString(4)
				
				/*
				4 bytes.
				Length data below, rounded up to an even byte count.
				*/
				size = fileData.readInt();
				size = (size + 1) & ~0x01;
				
				//remember previous position
				prevPos = fileData.position;
				
				// trace ("tag = "+tag);
				
				switch (tag)
				{
					//------------------------------------------------------------- get layer ID
					case "lyid": layerID 	= fileData.readInt(); break;
					
					//------------------------------------------------------------- get layer divider section
					case "lsct": readLayerSectionDevider(); break;
					
					//------------------------------------------------------------- get layer unicode name
					case "luni": nameUNI 	= fileData.readUTFBytes(4); break;
					
					//------------------------------------------------------------- get layer effects
					case "lrFX": parseLayerEffects(); break;
				}
				
				fileData.position += prevPos + size - fileData.position;
			}
			
			fileData.position += pos + extraSize - fileData.position;
		}
		
		
		private function parseLayerEffects() :void
		{
			filters_arr = new Array();
			
			var version			:int = fileData.readShort(); //fileData.readShort( length 2)
			var numEffects		:int = fileData.readShort(); //fileData.readShort( length 2)
			var remainingSize	:int;
			
			for ( var i:uint = 0; i < numEffects; ++i ) 
			{
				
				var sig:String = fileData.readUTFBytes(4);
				
				//check signature
				if (sig != "8BIM") throw new Error("layer effect information signature error");
				
				//check effect ID
				var effID:String = fileData.readUTFBytes(4);
				
				switch (effID) 
				{
					case "cmnS":		//common state info
						//skip 
						/*
						4 Size of next three items: 7
						4 Version: 0
						1 Visible: always true
						2 Unused: always 0
						*/
						fileData.position+=11;	
						break;
					
					case "dsdw":		//drop shadow
						remainingSize 				= fileData.readInt(); 
						parseDropShadow(fileData,false);
						break;
					
					case "isdw":		//inner drop shadow
						remainingSize 				= fileData.readInt(); 
						parseDropShadow(fileData,true);
						break;
					
					case "oglw":		//outer glow
						remainingSize 				= fileData.readInt(); 
						parseGlow(fileData,false);
						break;
					
					case "iglw":		//inner glow
						remainingSize 				= fileData.readInt(); 
						parseGlow(fileData,true);
						break;
					
					
					default : 
						fileData.position+=remainingSize;
						return;
				}
				
			}
			filters_arr.reverse();
		}		
		
		
		

		
		private function parseGlow(fileData:ByteArray, inner:Boolean = false):void
		{
			//4 Size of the remaining items: 41 or 51 (depending on version)
			var ver				:int 	= fileData.readInt(); 			//0 (Photoshop 5.0) or 2 (Photoshop 5.5)
			var blur			:int 	= fileData.readShort();			//Blur value in pixels (8)
			var intensity		:int	= fileData.readInt();				//Intensity as a percent (10?) (not working)
			
			fileData.position+=4;											//2 bytes for space
			var color_r:int = fileData.readUnsignedByte();
			fileData.position+=1;	
			var color_g:int = fileData.readUnsignedByte();
			fileData.position+=1;							
			var color_b:int = fileData.readUnsignedByte();
			
			//color shoul be 0xFFFF6633
			var colorValue		:uint = color_r<< 16 | color_g << 8 | color_b;
			
			fileData.position+=3;	
			
			var blendSig:String = fileData.readUTFBytes( 4 );
			if (blendSig != "8BIM") throw new Error("Invalid Blend mode signature for Effect: " + blendSig ); 
			
			/*
			4 bytes.
			Blend mode key.
			*/
			var blendModeKey:String = fileData.readUTFBytes( 4 );
			
			var effectIsEnabled:Boolean = fileData.readBoolean();			//1 Effect enabled
			
			var alpha : Number		= fileData.readUnsignedByte() /255;	 					//1 Opacity as a percent
			
			if (ver == 2)
			{
				if (inner) var invert:Boolean = fileData.readBoolean();	
				
				//get native color
				fileData.position+=4;											//2 bytes for space
				color_r = fileData.readUnsignedByte();
				fileData.position+=1;	
				color_g = fileData.readUnsignedByte();
				fileData.position+=1;							
				color_b = fileData.readUnsignedByte();
				fileData.position+=1;	
				
				var nativeColor		:uint = color_r<< 16 | color_g << 8 | color_b;
			}
			
			if (effectIsEnabled)
			{
				var glowFilter:GlowFilter	= new GlowFilter();
				glowFilter.alpha 			= alpha;
				glowFilter.blurX 			= blur;
				glowFilter.blurY 			= blur;
				glowFilter.color 			= colorValue;
				glowFilter.quality 			= 4;
				glowFilter.strength			= 1; //intensity isn't being passed correctly;
				glowFilter.inner 			= inner;
				
				filters_arr.push(glowFilter);
			}
		}		
		
		private function parseDropShadow(fileData:ByteArray, inner:Boolean = false):void
		{
						//4 Size of the remaining items: 41 or 51 (depending on version)
			var ver				:int 	= fileData.readInt(); 			//0 (Photoshop 5.0) or 2 (Photoshop 5.5)
			var blur			:int 	= fileData.readShort();			//Blur value in pixels (8)
			var intensity		:int 	= fileData.readInt();				//Intensity as a percent (10?)
			var angle			:int 	= fileData.readInt();				//Angle in degrees		(120)
			var distance		:int 	= fileData.readInt();				//Distance in pixels		(25)
			
			fileData.position+=4;											//2 bytes for space
			var color_r:int = fileData.readUnsignedByte();
			fileData.position+=1;	
			var color_g:int = fileData.readUnsignedByte();
			fileData.position+=1;							
			var color_b:int = fileData.readUnsignedByte();
			
			//color shoul be 0xFFFF6633
			var colorValue		:uint = color_r<< 16 | color_g << 8 | color_b;
			
			fileData.position+=3;	
			
			var blendSig:String = fileData.readUTFBytes( 4 );
			if (blendSig != "8BIM") throw new Error("Invalid Blend mode signature for Effect: " + blendSig ); 
			
			/*
			4 bytes.
			Blend mode key.
			*/
			var blendModeKey:String = fileData.readUTFBytes( 4 );
			
			var effectIsEnabled:Boolean = fileData.readBoolean();			//1 Effect enabled
			
			var useInAllEFX:Boolean = fileData.readBoolean();				//1 Use this angle in all of the layer effects
			
			var alpha : Number		= fileData.readUnsignedByte() /255;	 					//1 Opacity as a percent
			
			//get native color
			fileData.position+=4;											//2 bytes for space
			color_r = fileData.readUnsignedByte();
			fileData.position+=1;	
			color_g = fileData.readUnsignedByte();
			fileData.position+=1;							
			color_b = fileData.readUnsignedByte();
			fileData.position+=1;	
			
			var nativeColor		:uint = color_r<< 16 | color_g << 8 | color_b;
			
			if (effectIsEnabled)
			{
				var dropShadowFilter:DropShadowFilter = new DropShadowFilter();
				dropShadowFilter.alpha 		= alpha;
				dropShadowFilter.angle 		= 180 - angle;
				dropShadowFilter.blurX 		= blur;
				dropShadowFilter.blurY 		= blur;
				dropShadowFilter.color 		= colorValue;
				dropShadowFilter.quality 	= 4;
				dropShadowFilter.distance 	= distance;
				dropShadowFilter.inner 		= inner;
				dropShadowFilter.strength	= 1;
				
				filters_arr.push(dropShadowFilter);
				
				if (filters_arr.length == 2)
				{
					filters_arr.reverse();
				}
			}
		}		
		
		private function readRect():Rectangle
		{
			var y 		: int = fileData.readInt();
			var x 		: int = fileData.readInt();
			var bottom 	: int = fileData.readInt();
			var right 	: int = fileData.readInt();
			
			return new Rectangle(x,y,right-x, bottom-y);
		}
		
		private function readLayerSectionDevider() :void
		{
			var dividerType : int = fileData.readInt();
			
			switch (dividerType) 
			{
				case 0: type = LayerType_NORMAL;	 		break;
				case 1: type = LayerType_FOLDER_OPEN; 		break;
				case 2: type = LayerType_FOLDER_CLOSED; 	break; 
				case 3: type = LayerType_HIDDEN;			break;
			}
		}		

		//returns the read value and its length in format {str:value, length:size}
		private function readPascalStringObj():Object
		{
			var size:uint = fileData.readUnsignedByte();
			size += 3 - size % 4;
			return  {str:fileData.readMultiByte( size, "shift-jis").toString(), length:size + 1};
		}


		public function getBlendMode():String
		{
			switch(blendModeKey)
			{
				case "lddg" : return BlendMode.ADD ;
				case "dark" : return BlendMode.DARKEN ;
				case "diff" : return BlendMode.DIFFERENCE ;
				case "hLit" : return BlendMode.HARDLIGHT ;
				case "lite" : return BlendMode.LIGHTEN ;
				case "mul " : return BlendMode.MULTIPLY ;
				case "over" : return BlendMode.OVERLAY ;
				case "scrn" : return BlendMode.SCREEN ;
				case "fsub" : return BlendMode.SUBTRACT ;
				default 	: return BlendMode.NORMAL; 
			}
		}
		
			
			
		
		private function parseLayerMaskData( stream:ByteArray ):void 
		{
			//-------------------------------------------------------------  READING LAYER MASK
			/*
			4 bytes.
			Size of the data: 36, 20, or 0.
			If zero, the following fields are not present
			*/
			var maskSize:uint = stream.readUnsignedInt();
			
			if (!(maskSize == 0 || maskSize ==  20 || maskSize == 36))
			{
				throw new Error("Invalid mask size");
			}	
			
			if ( maskSize > 0 ) 
			{
				maskBounds2 = readRect();
				
				var defaultColor			: uint	= stream.readUnsignedByte(); // readTinyInt
				var flags					: uint	= stream.readUnsignedByte(); // readBits(1)
				
				if (maskSize == 20)
				{
					var maskPadding			: int	= stream.readInt(); // 723 (readShortInt)
				}
				else
				{
					var realFlags			: uint	= stream.readUnsignedByte();
					var realUserMaskBack	: uint	= stream.readUnsignedByte();
					
					maskBounds = readRect();
				}
			}
		}			
	}
}
