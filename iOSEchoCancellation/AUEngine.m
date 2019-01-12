//
//  AUEngine.m
//  AudioUnit VPIO Capture and Player
//
//  Created by wilsonc on 2019/1/11.
//  Copyright © 2019 oeichenwei@gmail.com. All rights reserved.
//

#import "AUEngine.h"
#import "SKAudioBuffer.h"
#import "SKAudioParser.h"
#import "SKAudioConverter.h"

typedef enum tagPlayMode
{
    Play_None,
    Play_MP3,
    Play_PCM
} PlayMode;

@interface AUEngine () <SKAudioParserDelegate>
{
    AVAudioSession* session;
    AUGraph graph;
    @public AudioUnit vpio;
    
    bool working;
    PlayMode playMode;
    
    //mp3 parser
    SKAudioParser *parser;
    SKAudioBuffer *buffer;
    SKAudioConverter *converter;
    
    @public void* recordBufffer;
    @public int bufferSize;
}

- (OSStatus)requestPlaybackFrames:(UInt32)inNumberOfFrames ioData:(AudioBufferList*)inIoData busNumber:(UInt32)inBusNumber;

@end

bool CheckError(OSStatus error, const char *operation)
{
    if (error == noErr)
        return false;
    
    char errorString[20] = {0};
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4]))
    {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    }
    NSLog(@"Error: %s (%s)\n", operation, errorString);
    return true;
}

#define CHECK_ERROR_RETURN_VOID(ret, errstr)     if (CheckError(ret, errstr)) return;

static OSStatus AUEngineInputCallback(void *userData,
                                      AudioUnitRenderActionFlags *ioActionFlags,
                                      const AudioTimeStamp *inTimeStamp,
                                      UInt32 inBusNumber,
                                      UInt32 inNumberFrames,
                                      AudioBufferList *ioData)
{
    AUEngine *self = (__bridge AUEngine *)userData;

    AudioBufferList inputData;
    inputData.mNumberBuffers = 1;
    inputData.mBuffers[0].mData = self->recordBufffer;
    inputData.mBuffers[0].mDataByteSize = inNumberFrames*2;
    inputData.mBuffers[0].mNumberChannels = 1;
    
    OSStatus ret = AudioUnitRender(self->vpio, ioActionFlags, inTimeStamp, 1, inNumberFrames, &inputData);
    if (!CheckError(ret, "AudioUnitRender failed"))
    {
        [self.delegate onDataArriving: self
                           packetData: inputData.mBuffers[0].mData
                           dataLength: inputData.mBuffers[0].mDataByteSize
                       bytesPerSample: 2];
    }

    return ret;
}

static OSStatus AUEngineRenderCallback(void *userData,
                                       AudioUnitRenderActionFlags *ioActionFlags,
                                       const AudioTimeStamp *inTimeStamp,
                                       UInt32 inBusNumber,
                                       UInt32 inNumberFrames,
                                       AudioBufferList *ioData)
{
    AUEngine* self = (__bridge AUEngine*)userData;
    
    return [self requestPlaybackFrames: inNumberFrames
                                ioData: ioData
                             busNumber: inBusNumber];
    return -1;
}

@implementation AUEngine

- (void)start
{
    if (working)
    {
        NSLog(@"engine is working, start failed.");
        return;
    }
    
    if (!session)
    {
        session = [AVAudioSession sharedInstance];
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        [session setActive:YES error:nil];
    }
    parser = [[SKAudioParser alloc] init];
    parser.delegate = self;
    buffer = [[SKAudioBuffer alloc] init];
    playMode = Play_None;
    
    bufferSize = 8192;
    recordBufffer = malloc(bufferSize);

    [self createAUGraph];
    
    working = true;
}

- (void)stop
{
    AUGraphStop(graph);
    AUGraphUninitialize(graph);
    DisposeAUGraph(graph);
    
    converter = nil;
    buffer = nil;
    parser = nil;

    working = false;
}

- (void)playMP3Data: (NSData*)data
{
    if (playMode != Play_None && playMode != Play_MP3)
    {
        NSLog(@"playMP3Data, it is already playing other formats (%d).", playMode);
        return;
    }
    playMode = Play_MP3;
    [parser parseData:data];
}

- (void)playPCMData: (NSData*)data
{
    if (playMode != Play_None && playMode != Play_PCM)
    {
        NSLog(@"playPCMData, it is already playing other formats (%d).", playMode);
        return;
    }
    playMode = Play_PCM;
    AudioStreamBasicDescription inDescription = LinearPCMStreamDescription(1);
    inDescription.mFramesPerPacket = 1024;
    if (!converter)
    {
        converter = [[SKAudioConverter alloc] initWithSourceFormat: &inDescription];
    }
    
    UInt32 dataSize = (UInt32)[data length];
    for (UInt32 i = 0; i < dataSize / (2 * inDescription.mFramesPerPacket); i++)
    {
        AudioStreamPacketDescription desc;
        desc.mStartOffset = i * inDescription.mFramesPerPacket * 2;
        desc.mVariableFramesInPacket = 1;
        desc.mDataByteSize = inDescription.mFramesPerPacket * 2;
        [buffer storePacketData:[data bytes] dataLength:dataSize packetDescriptions:&desc packetsCount:1];
    }
}

-(void)createAUGraph
{
    OSStatus ret;
    ret = NewAUGraph(&graph);
    CHECK_ERROR_RETURN_VOID(ret, "NewAUGraph failed");
    
    //Create nodes and add to the graph
    //Set up a RemoteIO for synchronously playback
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    //we can access the system's echo cancellation by using kAudioUnitSubType_VoiceProcessingIO subtype
    inputcd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AUNode vpioNode;
    //Add node to the graph
    ret = AUGraphAddNode(graph, &inputcd, &vpioNode);
    CHECK_ERROR_RETURN_VOID(ret, "AUGraphAddNode failed");
    
    //Open the graph
    ret = AUGraphOpen(graph);
    CHECK_ERROR_RETURN_VOID(ret, "AUGraphOpen failed");
    
    //Get reference to the node
    ret = AUGraphNodeInfo(graph, vpioNode, &inputcd, &vpio);
    CHECK_ERROR_RETURN_VOID(ret, "AUGraphNodeInfo failed");
    
    //Open input of the bus 1(input mic)
    UInt32 enableFlag = 1;
    ret = AudioUnitSetProperty(vpio, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input,
                               1, &enableFlag, sizeof(enableFlag));
    CHECK_ERROR_RETURN_VOID(ret, "Open input of bus 1 failed");
    
    //Open output of bus 0(output speaker)
    ret = AudioUnitSetProperty(vpio, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output,
                               0, &enableFlag, sizeof(enableFlag));
    CHECK_ERROR_RETURN_VOID(ret, "Open output of bus 0 failed");
    
    //Set up stream format for input and output
    AudioStreamBasicDescription streamFormat = LinearPCMStreamDescription(2);
    ret = AudioUnitSetProperty(vpio, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                               0, &streamFormat, sizeof(streamFormat));
    CHECK_ERROR_RETURN_VOID(ret, "kAudioUnitProperty_StreamFormat of bus 0 failed");
    
    streamFormat = LinearPCMStreamDescription(1);
    ret = AudioUnitSetProperty(vpio, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
                               1, &streamFormat, sizeof(streamFormat));
    CHECK_ERROR_RETURN_VOID(ret, "kAudioUnitProperty_StreamFormat of bus 1 failed");
    
    //Set up input callback
    AURenderCallbackStruct render;
    render.inputProc = AUEngineRenderCallback;
    render.inputProcRefCon = (__bridge void *)self;
    ret = AudioUnitSetProperty(vpio, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global,
                               0, &render, sizeof(render));
    CHECK_ERROR_RETURN_VOID(ret, "kAudioUnitProperty_SetRenderCallback failed");
    
    AURenderCallbackStruct input;
    input.inputProc = AUEngineInputCallback;
    input.inputProcRefCon = (__bridge void *)self;
    ret = AudioUnitSetProperty(vpio, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global,
                               1, &input, sizeof(input));
    CHECK_ERROR_RETURN_VOID(ret, "kAudioOutputUnitProperty_SetInputCallback failed");

    ret = AUGraphInitialize(graph);
    CHECK_ERROR_RETURN_VOID(ret, "AUGraphInitialize failed");
    
    ret = AUGraphStart(graph);
    CHECK_ERROR_RETURN_VOID(ret, "AUGraphStart failed");
}

- (UInt32)toggleAEC
{
    if (!vpio)
        return -3;
    
    UInt32 echoCancellation = 0;
    UInt32 size = sizeof(echoCancellation);
    OSStatus ret = AudioUnitGetProperty(vpio, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global,
                                        0, &echoCancellation, &size);
    if (CheckError(ret, "kAUVoiceIOProperty_BypassVoiceProcessing failed"))
        return -1;
    
    if (echoCancellation == 0) {
        echoCancellation = 1;
    } else {
        echoCancellation = 0;
    }
    
   ret = AudioUnitSetProperty(vpio, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global,
                              0, &echoCancellation, sizeof(echoCancellation));
   if(CheckError(ret, "AudioUnitSetProperty kAUVoiceIOProperty_BypassVoiceProcessing failed"))
       return -2;

    return echoCancellation;
}

- (void)audioStreamParser:(SKAudioParser *)inParser didObtainStreamDescription:(AudioStreamBasicDescription *)inDescription
{
    NSLog(@"mSampleRate: %f", inDescription->mSampleRate);
    NSLog(@"mFormatID: %u", (unsigned int)inDescription->mFormatID);
    NSLog(@"mFormatFlags: %u", (unsigned int)inDescription->mFormatFlags);
    NSLog(@"mBytesPerPacket: %u", (unsigned int)inDescription->mBytesPerPacket);
    NSLog(@"mFramesPerPacket: %u", (unsigned int)inDescription->mFramesPerPacket);
    NSLog(@"mBytesPerFrame: %u", (unsigned int)inDescription->mBytesPerFrame);
    NSLog(@"mChannelsPerFrame: %u", (unsigned int)inDescription->mChannelsPerFrame);
    NSLog(@"mBitsPerChannel: %u", (unsigned int)inDescription->mBitsPerChannel);
    NSLog(@"mReserved: %u", (unsigned int)inDescription->mReserved);
    
    converter = [[SKAudioConverter alloc] initWithSourceFormat:inDescription];
}

- (void)audioStreamParser:(SKAudioParser *)inParser packetData:(const void * )inBytes dataLength:(UInt32)inLength packetDescriptions:(AudioStreamPacketDescription* )inPacketDescriptions packetsCount:(UInt32)inPacketsCount
{
    [buffer storePacketData:inBytes dataLength:inLength packetDescriptions:inPacketDescriptions packetsCount:inPacketsCount];
}

- (OSStatus)requestPlaybackFrames:(UInt32)inNumberOfFrames ioData:(AudioBufferList*)inIoData busNumber:(UInt32)inBusNumber
{
    if (!converter)
        return -1;
    
    if (buffer.availablePacketCount < converter.packetsPerSecond * 4) {
        return -1;
    }
    return [converter requestNumberOfFrames:inNumberOfFrames ioData:inIoData busNumber:inBusNumber buffer:buffer];
}

@end
