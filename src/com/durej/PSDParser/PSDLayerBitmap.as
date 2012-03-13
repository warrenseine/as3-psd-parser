package com.durej.PSDParser 
{
	import flash.geom.Rectangle;
	import flash.display.BitmapData;
	import flash.utils.ByteArray;
	/**
	 * @author Slavomir Durej
	 */


	public class PSDLayerBitmap 
	{

		private var layer 			: PSDLayer;
		private var fileData 		: ByteArray;
		private var lineLengths 	: Array;

		public var channels 		: Array;
		public var image 			: BitmapData;
		private var width 			: int;
		private var height 			: int;

		
		public function PSDLayerBitmap ( layer:PSDLayer, fileData:ByteArray) 
		{
			this.layer 				= layer;
			this.fileData 			= fileData;

			readChannels();
		}
		
		private function readChannels():void
		{
			//init image channels
			channels		= [];
			channels["a"] 	= [];
			channels["r"] 	= [];
			channels["g"] 	= [];
			channels["b"] 	= [];
			
			var channelsLength:int = layer.channelsInfo_arr.length;
			
			var isTransparent:Boolean = (channelsLength > 3);
			
			if (layer.type != PSDLayer.LayerType_NORMAL)
			{
				var pixelDataSize:int;
				
				for ( var i:int = 0; i < channelsLength; ++i ) 
				{
					var channelLenghtInfo	:PSDChannelInfoVO = layer.channelsInfo_arr[i];
					pixelDataSize+=channelLenghtInfo.length;
				}
				//skip image data parsing for layer folders (for now)
				fileData.position+= pixelDataSize;
				return;
			}

			for ( i = 0; i < channelsLength; ++i ) 
			{
				channelLenghtInfo	 			= layer.channelsInfo_arr[i];
				var channelID			:int 	= channelLenghtInfo.id;
				var channelLength		:uint 	= channelLenghtInfo.length;
				
				//determine the correct width and height
				if (channelID < -1) 
				{
					//use the mask dimensions
					width 	= layer.maskBounds.width;
					height 	= layer.maskBounds.height;
				}
				else
				{
					//use the layer dimensions
					width 	= layer.bounds.width;
					height 	= layer.bounds.height;	
				}
				
				
				if ((width*height) == 0) //TODO fix this later
				{
					var compression:int = fileData.readShort();
					return;
				}
				
				var channelData:ByteArray = readColorPlane(i,height,width, channelLength);
				
				if (channelData.length == 0) return; //TODO fix this later				

				if (channelID == -1)
				{
					channels["a"] = channelData; 
					//TODO implement [int(ch * opacity_devider) for ch in channel] ; from pascal
				}
				else if (channelID == 0)
				{
					channels["r"] 	= channelData;
				}
				else if (channelID == 1)
				{
					channels["g"] 	= channelData;
				}
				else if (channelID == 2)
				{
					channels["b"] 	= channelData;
				}
				else if (channelID < -1)
				{
					channels["a"] = channelData;
					//TODO implement : [int(a * (c/255)) for a, c in zip(self.channels["a"], channel)] from pascal
				}
			}
			
			renderImage(isTransparent);
		}
	
		private function readColorPlane(planeNum:int,height:int, width:int, channelLength:int):ByteArray
		{
			var channelDataSize:int = width * height;
			var isRLEncoded:Boolean = false;
			var imageData:ByteArray;
			var i:int;

			imageData = new ByteArray();
			
			var compression:int = fileData.readShort();
			isRLEncoded = (compression == 1);
			
			if (isRLEncoded)
			{
				lineLengths = new Array(height);
				
				for ( i = 0; i < height; ++i ) 
				{
					lineLengths[i] = fileData.readUnsignedShort();
				}
				//read compressed chanel data 
				for ( i = 0; i < height; ++i ) 
				{
					var line:ByteArray = new ByteArray();
					fileData.readBytes( line, 0, lineLengths[i] );
					imageData.writeBytes( unpack( line ) );
				}
			}
			else
			{
				if (compression == 0)
				{
					//read raw data
					fileData.readBytes( imageData, 0,  channelDataSize);
				}
				else
				{
					//skip data
					fileData.position+=channelLength;
				}
			}

			return imageData;	
		}
	
	
	
		
		private function renderImage( transparent:Boolean = false ):void 
		{
			if (transparent) image = new BitmapData( width, height, true, 0x00000000 );
			else image = new BitmapData( width, height, false, 0x000000 );
			
			//init alpha channel
			if (transparent)
			{
				var a:ByteArray = channels["a"];
				a.position = 0;
			}
			
			var onlyTransparent:Boolean = (channels["r"].length == 0 && channels["g"].length == 0 && channels["b"].length == 0);
			
			if (!onlyTransparent)
			{
				//init channels
				var r:ByteArray = channels["r"];
				var g:ByteArray = channels["g"];
				var b:ByteArray = channels["b"];
				
				//reset position
				r.position = 0;
				g.position = 0;
				b.position = 0;
			}

			var color:uint;
			
			for ( var y:int = 0; y < height; ++y ) 
			{
				for ( var x:int = 0; x < width; ++x ) 
				{
					if (onlyTransparent)
					{
						color = a.readUnsignedByte();
						image.setPixel32( x, y, color);
					}
					else
					{
						if (transparent)
						{
							color = a.readUnsignedByte() << 24 | r.readUnsignedByte() << 16 | g.readUnsignedByte() << 8 | b.readUnsignedByte();
							image.setPixel32( x, y, color);
						}
						else
						{
							color = r.readUnsignedByte() << 16 | g.readUnsignedByte() << 8 | b.readUnsignedByte();	
							image.setPixel( x, y, color );
						}
					}
				}
			}
		}
		
		
		
		public function unpack( packed:ByteArray ):ByteArray 
		{
			var i:int;
			var n:int;
			var byte:int;
			var unpacked:ByteArray = new ByteArray();
			var count:int;
			
			while ( packed.bytesAvailable ) 
			{
				n = packed.readByte();
				
				if ( n >= 0 ) 
				{
					count = n + 1;
					for ( i = 0; i < count; ++i ) 
					{
						unpacked.writeByte( packed.readByte() );
					}
				} 
				else 
				{
					byte = packed.readByte();
					
					count = 1 - n;
					for ( i = 0; i < count; ++i ) 
					{
						unpacked.writeByte( byte );
					}
				}
			}
			
			return unpacked;
		}		
	}
}
