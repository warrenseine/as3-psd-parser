package com.durej.PSDParser 
{
	import flash.utils.ByteArray;
	/**
	 * @author Slavomir Durej
	 */
	public class PSDChannelInfoVO 
	{
		public var id : int;
		public var length : uint;

		public function PSDChannelInfoVO(fileData : ByteArray) 
		{
			id 		= fileData.readShort();
			length 	= fileData.readUnsignedInt();			
		}
	}
}
