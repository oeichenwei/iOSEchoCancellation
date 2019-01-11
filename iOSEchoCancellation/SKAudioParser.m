//
//  SKAudioParser.m
//  SKAudioQueue
//
//  Created by steven on 2015/1/22.
//  Copyright (c) 2015年 KKBOX. All rights reserved.
//

#import "SKAudioParser.h"

@implementation SKAudioParser


void audioFileStreamPropertyListenerProc(void *inClientData, AudioFileStreamID	inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
	if (inPropertyID == 'dfmt') {
		AudioStreamBasicDescription description;
		UInt32 descriptionSize = sizeof(description);
		AudioFileStreamGetProperty(inAudioFileStream, inPropertyID, &descriptionSize, &description);
		[((__bridge SKAudioParser *)inClientData).delegate audioStreamParser:(__bridge SKAudioParser *)inClientData didObtainStreamDescription:&description];
	}
}


void audioFileStreamPacketsProc(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription	*inPacketDescriptions)
{
	[((__bridge SKAudioParser *)inClientData).delegate audioStreamParser:((__bridge SKAudioParser *)inClientData) packetData:inInputData dataLength:inNumberBytes packetDescriptions:inPacketDescriptions packetsCount:inNumberPackets];
	
}

- (id)init
{
	self = [super init];
	if (self) {
		
		AudioFileStreamOpen((__bridge void *)(self), audioFileStreamPropertyListenerProc, audioFileStreamPacketsProc, kAudioFileMP3Type, &audioFileStreamID);
		
	}
	return self;
}

- (void)parseData:(NSData *)inData
{
	AudioFileStreamParseBytes(audioFileStreamID, (UInt32)[inData length], [inData bytes], 0);
}

@synthesize delegate;
@end
