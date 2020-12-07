//
//  MSVideoEncoder.h
//  LiveShowCD
//
//  Created by mysoul on 2020/12/3.
//

#import <Foundation/Foundation.h>
#import "MSDefineHeader.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSVideoEncoder : NSObject

/// Frame rate, default 25
@property(nonatomic, assign)int fps;
/// Bit rate, default 512*1024
@property(nonatomic, assign)int bitRate;
/// Key frame interval, default 60s
@property(nonatomic, assign)int keyFrameInterval;
/// Average encoding rate, default @[@(bitRate * 1.5/8), @(1)];
@property (nonatomic) NSArray * limit;
/// video qualiy, default HD 1280 x 720
@property(nonatomic, assign)EncodeVideoQuality videoQuality;

/// Encode frame error block
@property(nonatomic, copy)void (^ErrorBlock)(NSString * _Nullable error);

- (instancetype)init;

/// Setting encode video quality
- (void)setEncodeVideoQuality:(EncodeVideoQuality)quality;

/// Encoding camera output samples
/// @param sampleBuffer sample buffer
/// @param block encoded video data block
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer outputData:(VideoEncodeDataBlock)block;

/// Release encoder
- (void)releaseCompressionSession;

@end

NS_ASSUME_NONNULL_END
