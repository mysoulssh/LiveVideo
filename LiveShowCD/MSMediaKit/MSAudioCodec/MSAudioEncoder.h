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

@end

NS_ASSUME_NONNULL_END
