//
//  SKAudioConverter.m
//  SimplePlaying
//
//  Created by StevenKuo on 2015/11/11.
//  Copyright © 2015年 StevenKuo. All rights reserved.
//

#import "SKAudioConverter.h"

static OSStatus AudioConverterFiller(AudioConverterRef inAudioConverter, UInt32* ioNumberDataPackets, AudioBufferList* ioData, AudioStreamPacketDescription** outDataPacketDescription, void* inUserData);

OSStatus AudioConverterFiller (AudioConverterRef inAudioConverter, UInt32* ioNumberDataPackets, AudioBufferList* ioData, AudioStreamPacketDescription** outDataPacketDescription, void* inUserData)
{
    NSArray *args = (__bridge NSArray *)inUserData;
    SKAudioConverter *self = args[0];
    SKAudioBuffer *buffer = args[1];
    //    *ioNumberDataPackets = 1;
    [self _fillBufferlist:ioData withBuffer:buffer packetDescription:outDataPacketDescription];
    return noErr;
}

AudioStreamBasicDescription LinearPCMStreamDescription(int channel)
{
    AudioStreamBasicDescription destFormat;
    bzero(&destFormat, sizeof(AudioStreamBasicDescription));
    destFormat.mSampleRate = 44100.0;
    destFormat.mFormatID = kAudioFormatLinearPCM;
    destFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;
    
    destFormat.mFramesPerPacket = 1;
    destFormat.mBytesPerPacket = 2 * channel;
    destFormat.mBytesPerFrame = 2 * channel;
    destFormat.mChannelsPerFrame = channel;
    destFormat.mBitsPerChannel = 16;
    destFormat.mReserved = 0;
    return destFormat;
}

@implementation SKAudioConverter

- (instancetype)initWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat
{
    self = [super init];
    if (self) {
        audioStreamDescription = *sourceFormat;
        destFormat = LinearPCMStreamDescription(2);
        AudioConverterNew(&audioStreamDescription, &destFormat, &converter);
        
        UInt32 packetSize = 44100 * 4;
        renderBufferSize = packetSize;
        renderBufferList = (AudioBufferList *)calloc(1, sizeof(UInt32) + sizeof(AudioBuffer));
        renderBufferList->mNumberBuffers = 1;
        renderBufferList->mBuffers[0].mNumberChannels = 2;
        renderBufferList->mBuffers[0].mDataByteSize = packetSize;
        renderBufferList->mBuffers[0].mData = calloc(1, packetSize);
    }
    return self;
}

- (void)_fillBufferlist:(AudioBufferList *)ioData withBuffer:(SKAudioBuffer *)buffer packetDescription:(AudioStreamPacketDescription** )outDataPacketDescription
{
    static AudioStreamPacketDescription aspdesc;
    
    AudioPacketInfo currentPacketInfo = buffer.currentPacketInfo;
    
    void *data = currentPacketInfo.data;
    UInt32 length = (UInt32)currentPacketInfo.packetDescription.mDataByteSize;
    ioData->mBuffers[0].mData = data;
    ioData->mBuffers[0].mDataByteSize = length;
    ioData->mNumberBuffers = 1;
    
    *outDataPacketDescription = &aspdesc;
    aspdesc.mDataByteSize = length;
    aspdesc.mStartOffset = 0;
    aspdesc.mVariableFramesInPacket = 1;
    
    [buffer movePacketReadIndex];
}

- (OSStatus)requestNumberOfFrames:(UInt32)inNumberOfFrames ioData:(AudioBufferList  *)inIoData busNumber:(UInt32)inBusNumber buffer:(SKAudioBuffer *)inBuffer
{
    if (destFormat.mFormatID == audioStreamDescription.mFormatID && destFormat.mChannelsPerFrame == audioStreamDescription.mChannelsPerFrame*2)
    {
        //TODO here hard coded, the length may not match, need to copy to an intermittent buffer
        AudioPacketInfo currentPacketInfo = inBuffer.currentPacketInfo;
        if (![inBuffer hasMoreData])
            return -1;
        void *data = currentPacketInfo.data;
        UInt32 length = (UInt32)currentPacketInfo.packetDescription.mDataByteSize;
        for (UInt32 i = 0; i < length / audioStreamDescription.mBytesPerFrame; i++)
        {
            memcpy(inIoData->mBuffers[0].mData + 4 * i, data + 2 * i, 2);
            memcpy(inIoData->mBuffers[0].mData + 4 * i + 2, data + 2 * i, 2);
        }
        
        [inBuffer movePacketReadIndex];
        
        return noErr;
    }
    
    UInt32 packetSize = inNumberOfFrames;
    NSArray *args = @[self, inBuffer];
    OSStatus status = noErr;
    
    status = AudioConverterFillComplexBuffer(converter, AudioConverterFiller, (__bridge void *)(args), &packetSize, renderBufferList, NULL);
    
    if (noErr == status && packetSize) {
        inIoData->mNumberBuffers = 1;
        inIoData->mBuffers[0].mNumberChannels = 2;
        inIoData->mBuffers[0].mDataByteSize = renderBufferList->mBuffers[0].mDataByteSize;
        inIoData->mBuffers[0].mData = renderBufferList->mBuffers[0].mData;
        status = noErr;
    }
    return status;
}

- (double)packetsPerSecond
{
    if (!(audioStreamDescription.mFramesPerPacket > 0)) {
        return 0;
    }
    return audioStreamDescription.mSampleRate / audioStreamDescription.mFramesPerPacket;
}

@end
