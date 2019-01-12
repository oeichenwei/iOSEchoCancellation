#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AUEngine;

@protocol AUEngineDelegate <NSObject>

- (void)onDataArriving:(AUEngine *)engine packetData:(const void * )inBytes dataLength:(UInt32)inLength bytesPerSample:(int)inBytesPerSample;

@end


@interface AUEngine : NSObject

- (void)start;

- (void)stop;

- (UInt32)toggleAEC;

- (void)playMP3Data: (NSData*)data;

- (void)playPCMData: (NSData*)data;

@property (weak, nonatomic) id <AUEngineDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
