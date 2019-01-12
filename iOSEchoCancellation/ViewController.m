//
//  ViewController.m
//  iOSEchoCancellation
//
//  Created by 李 行 on 15/4/12.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "AUEngine.h"

@interface ViewController () <AUEngineDelegate>
{
    AUEngine* engine;
    FILE* fpRecord;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    engine = [[AUEngine alloc] init];
    engine.delegate = self;

    [self addControlButton];
}

-(void)addControlButton{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.frame = CGRectMake(60, 60, 200, 50);
    [button setTitle:@"Echo cancellation is open" forState:UIControlStateNormal];
    [button.titleLabel setTextAlignment:NSTextAlignmentCenter];
    [button addTarget:self action:@selector(openOrCloseEchoCancellation:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

-(void)openOrCloseEchoCancellation:(UIButton*)button
{
    UInt32 echoCancellation = [engine toggleAEC];
    
    [button setTitle:echoCancellation==0?@"Echo cancellation is open":@"Echo cancellation is closed" forState:UIControlStateNormal];
}

- (NSString*)FilePathForResourceName: (NSString*) name
                           extension: (NSString*) extension
{
    NSString* file_path = [[NSBundle mainBundle] pathForResource:name ofType:extension];
    if (file_path == NULL) {
        NSLog(@"Couldn't find '%@.%@' in bundle.", name, extension);
        exit(-1);
    }
    return file_path;
}

- (void)onDataArriving:(AUEngine *)engine
            packetData:(const void * )inBytes
            dataLength:(UInt32)inLength
        bytesPerSample:(int)inBytesPerSample
{
    if (fpRecord)
        fwrite(inBytes, 1, inLength, fpRecord);
}

- (IBAction)onButtonStart :(id)sender
{
    NSString* fullRecordFileName = [self generateFilePath: @"temp.pcm"];
    fpRecord = fopen([fullRecordFileName UTF8String], "wb");
    
    [engine start];
    
    NSString* mp3FilePath = [self FilePathForResourceName: @"dear" extension: @"mp3"];
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:mp3FilePath];
    
    [engine playMP3Data: data];
}

- (IBAction)onButtonStop:(id)sender
{
    [engine stop];
    fclose(fpRecord);
}

- (IBAction)onButtonPlayback:(id)sender
{
    NSString* fullRecordFileName = [self generateFilePath: @"temp.pcm"];
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:fullRecordFileName];

    [engine start];
    [engine playPCMData:data];
}

-(NSString*)generateFilePath: (NSString*)filename
{
    NSArray *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* doc_path = [path objectAtIndex:0];

    return [doc_path stringByAppendingPathComponent:filename];
}

@end
