//
//  MSAudioEncoder.m
//  LiveShowCD
//
//  Created by mysoul on 2020/12/15.
//

#import "MSAudioEncoder.h"

@interface MSAudioEncoder()
{
    CMAudioFormatDescriptionRef _audioFormatDescriptionRef;
}
@end

@implementation MSAudioEncoder

- (instancetype)initWithAudioDataType:(AudioDataType)audioDataType {
    if (self = [super init]) {
        self. audioDataType = audioDataType;
    }
    return self;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.audioDataType = AudioDataTypeAAC;
    }
    return self;
}

- (void)initEncoderWithSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    _audioFormatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription streamBasicDes = *CMAudioFormatDescriptionGetStreamBasicDescription(_audioFormatDescriptionRef);
    
    AudioStreamBasicDescription outStreamBasicDescription = {0};
    outStreamBasicDescription.mSampleRate = streamBasicDes.mSampleRate;
    outStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC;
    outStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC;
    outStreamBasicDescription.mBytesPerPacket = 0;
    outStreamBasicDescription.mFramesPerPacket = 1024;
    outStreamBasicDescription.mBytesPerFrame = 0;
    outStreamBasicDescription.mChannelsPerFrame = 1;
    outStreamBasicDescription.mBitsPerChannel = 0;
    outStreamBasicDescription.mReserved = 0;
    
}

@end
