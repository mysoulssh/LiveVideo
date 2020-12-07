//
//  MSVideoDecoder.h
//  LiveShowCD
//
//  Created by mysoul on 2020/12/7.
//

#import <Foundation/Foundation.h>
#import "MSDefineHeader.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSVideoDecoder : NSObject

/// Default width from video data
@property(nonatomic, assign)int32_t width;
/// Default height from video data
@property(nonatomic, assign)int32_t height;

/// Video DecoderBlock
@property(nonatomic, copy)VideoDecodeDataBlock outputDataBlock;

@property(nonatomic, assign)VideoDataType videoDecodeDataType;

/// Decode video data
/// @param naluData Nalu data
- (void)decodeVideoDataWithNaluData:(NSData *)naluData;

@end

NS_ASSUME_NONNULL_END
