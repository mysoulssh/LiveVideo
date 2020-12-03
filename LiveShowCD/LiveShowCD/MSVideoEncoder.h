//
//  MSVideoEncoder.h
//  LiveShowCD
//
//  Created by mysoul on 2020/12/3.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^VideoEncodeDataBlock)(NSData * data);

@interface MSVideoEncoder : NSObject

/// Frame rate, default 30
@property(nonatomic, assign)int fps;
/// Bit rate, default (width * height * 3 * 4 * 8)
@property(nonatomic, assign)int bitRate;
/// Key frame interval, default 60s
@property(nonatomic, assign)int keyFrameInterval;
/// Average encoding rate, default @[@(bitRate * 1.5/8), @(1)];
@property (nonatomic) NSArray * limit;

/// Encode frame error block
@property(nonatomic, copy)void (^ErrorBlock)(NSString * _Nullable error);

- (instancetype)init;

/// Encoding camera output samples
/// @param sampleBuffer sample buffer
/// @param block encoded video data block
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer outputData:(VideoEncodeDataBlock)block;

/// Release encoder
- (void)releaseCompressionSession;

@end

NS_ASSUME_NONNULL_END
