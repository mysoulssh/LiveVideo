//
//  MSAudioEncoder.h
//  LiveShowCD
//
//  Created by mysoul on 2020/12/15.
//

#import <Foundation/Foundation.h>
#import "MSDefineHeader.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSAudioEncoder : NSObject

@property(nonatomic, assign)AudioDataType audioDataType;

- (instancetype)initWithAudioDataType:(AudioDataType)audioDataType;

- (void)encodeAudioDataWithSampleBuffer:(CMSampleBufferRef)sampleBuffer encodeDataBlock:(AudioEncodeDataBlock)encodeBlock;

@end

NS_ASSUME_NONNULL_END
