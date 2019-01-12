//
//  SKAudioBuffer.m
//  SKAudioQueue
//
//  Created by steven on 2015/1/22.
//  Copyright (c) 2015年 KKBOX. All rights reserved.
//

#import "SKAudioBuffer.h"

@implementation SKAudioBuffer

- (id)init
{
    self = [super init];
    if (self) {
        
        packetCount = 2048;
        packets = (AudioPacketInfo *)calloc(packetCount, sizeof(AudioPacketInfo));
        
        audioData = [[NSMutableData alloc] init];
        packetDescData = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)storePacketData:(const void * )inBytes dataLength:(UInt32)inLength packetDescriptions:(AudioStreamPacketDescription* )inPacketDescriptions packetsCount:(UInt32)inPacketsCount
{
    @synchronized (self) {
        for (size_t index = 0; index < inPacketsCount; index ++) {
            
            if (packetWriteIndex >= packetCount) {
                size_t oldSize = packetCount * sizeof(AudioPacketInfo);
                packetCount = packetCount * 2;
                packets = (AudioPacketInfo *)realloc(packets, packetCount * sizeof(AudioPacketInfo));
                bzero((void *)packets + oldSize, oldSize);
            }
            AudioStreamPacketDescription emptyDescription;
            
            if (!inPacketDescriptions) {
                emptyDescription.mStartOffset = index;
                emptyDescription.mDataByteSize = 1;
                emptyDescription.mVariableFramesInPacket = 0;
            }
            
            AudioStreamPacketDescription *currentDescription = inPacketDescriptions ? &(inPacketDescriptions[index]) : &emptyDescription;
            
            AudioPacketInfo *nextInfo = &packets[packetWriteIndex];
            if (nextInfo->data) {
                free(nextInfo->data);
                nextInfo->data = NULL;
            }
            nextInfo->data = malloc(currentDescription->mDataByteSize);
            NSAssert(nextInfo->data, @"Must allocate memory for current packet");
            memcpy(nextInfo->data, inBytes + currentDescription->mStartOffset, currentDescription->mDataByteSize);
            memcpy(&nextInfo->packetDescription, currentDescription, sizeof(AudioStreamPacketDescription));
            
            packetWriteIndex++;
            
            _availablePacketCount++;
        }
    }
}

- (bool)hasMoreData
{
    return packetReadIndex < _availablePacketCount;
}

- (void)setPacketReadIndex:(size_t)inNewIndex
{
    size_t max = _availablePacketCount;
    
    if (inNewIndex > max) {
        packetReadIndex = max;
        return;
    }
    
    if (inNewIndex < packetWriteIndex) {
        packetReadIndex = inNewIndex;
    }
    else {
        packetReadIndex = packetWriteIndex;
    }
}

- (void)movePacketReadIndex
{
    [self setPacketReadIndex:packetReadIndex + 1];
}

- (AudioPacketInfo)currentPacketInfo
{
    return packets[packetReadIndex];
}

@synthesize delegate;
@synthesize currentPacketInfo;
@end
