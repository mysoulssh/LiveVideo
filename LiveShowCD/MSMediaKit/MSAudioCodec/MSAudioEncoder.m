//
//  MSAudioEncoder.m
//  LiveShowCD
//
//  Created by mysoul on 2020/12/15.
//

#import "MSAudioEncoder.h"

@interface MSAudioEncoder()
@property (nonatomic) dispatch_queue_t encoderQueue;
@property (nonatomic) dispatch_queue_t callbackQueue;

@property (nonatomic) AudioConverterRef audioConverter;
@property (nonatomic) uint8_t *aacBuffer;
@property (nonatomic) NSUInteger aacBufferSize;
@property (nonatomic) char *pcmBuffer;
@property (nonatomic) size_t pcmBufferSize;

@end

@implementation MSAudioEncoder

- (instancetype)initWithAudioDataType:(AudioDataType)audioDataType {
    if (self = [super init]) {
        self. audioDataType = audioDataType;
        [self configure];
    }
    return self;
}

- (instancetype)init {
    if (self = [super init]) {
        self.audioDataType = AudioDataTypeAAC;
        [self configure];
    }
    return self;
}

- (void)configure {
    _encoderQueue = dispatch_queue_create("AAC Encoder Queue", DISPATCH_QUEUE_SERIAL);
    _callbackQueue = dispatch_queue_create("AAC Encoder Callback Queue", DISPATCH_QUEUE_SERIAL);
    _audioConverter = NULL;
    _pcmBufferSize = 0;
    _pcmBuffer = NULL;
    _aacBufferSize = 1024;
    _aacBuffer = malloc(_aacBufferSize * sizeof(uint8_t));
    memset(_aacBuffer, 0, _aacBufferSize);
}

- (void) setupEncoderFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    AudioStreamBasicDescription inAudioStreamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
    // 初始化输出流的结构体描述为0. 很重要。
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    // inAudioStreamBasicDescription.mSampleRate;
    // 音频流，在正常播放情况下的帧率。如果是压缩的格式，这个属性表示解压缩后的帧率。帧率不能为0。
    outAudioStreamBasicDescription.mSampleRate = 8000;
    // 设置编码格式
    outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC;
    // 无损编码 ，0表示没有
    outAudioStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC;
    //每一个packet的音频数据大小。如果的动态大小，设置为0。动态大小的格式，需要用AudioStreamPacketDescription 来确定每个packet的大小。
    outAudioStreamBasicDescription.mBytesPerPacket = 0;
    //每个packet的帧数。如果是未压缩的音频数据，值是1。动态码率格式，这个值是一个较大的固定数字，比如说AAC的1024。如果是动态大小帧数（比如Ogg格式）设置为0。
    outAudioStreamBasicDescription.mFramesPerPacket = 1024;
    //每帧的大小。每一帧的起始点到下一帧的起始点。如果是压缩格式，设置为0 。
    outAudioStreamBasicDescription.mBytesPerFrame = 0;
    // 声道数
    outAudioStreamBasicDescription.mChannelsPerFrame = 1;
    // 压缩格式设置为0
    outAudioStreamBasicDescription.mBitsPerChannel = 0;
    // 8字节对齐，填0.
    outAudioStreamBasicDescription.mReserved = 0;
    //软编码
    AudioClassDescription *description = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, description, &_audioConverter); // 创建转换器
    if (status != 0) {
        NSLog(@"setup converter: %d", (int)status);
    }
    
    if (status == noErr) {
        UInt32 bitRate = 8000;
        UInt32 size = sizeof(bitRate);
        AudioConverterSetProperty(_audioConverter,
                                  kAudioConverterEncodeBitRate,
                                  size,
                                  &bitRate);
    }
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    UInt32 encoderSpecifier = type;
    OSStatus st;
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                    sizeof(encoderSpecifier),
                                    &encoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int)(st));
        return nil;
    }
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
            (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    return nil;
}

OSStatus inInputDataProcess(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    MSAudioEncoder *encoder = (__bridge MSAudioEncoder *)(inUserData);
    UInt32 requestedPackets = *ioNumberDataPackets;
    size_t copiedSamples = [encoder copyPCMSamplesIntoBuffer:ioData];
    if (copiedSamples < requestedPackets) {
        //PCM 缓冲区还没满
        *ioNumberDataPackets = 0;
        return -1;
    }
    *ioNumberDataPackets = 1;
    return noErr;
}

- (size_t)copyPCMSamplesIntoBuffer:(AudioBufferList*)ioData {
    size_t originalBufferSize = _pcmBufferSize;
    if (!originalBufferSize) {
        return 0;
    }
    ioData->mBuffers[0].mData = _pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = (int)_pcmBufferSize;
    _pcmBuffer = NULL;
    _pcmBufferSize = 0;
    return originalBufferSize;
}

- (void)encodeAudioDataWithSampleBuffer:(CMSampleBufferRef)sampleBuffer encodeDataBlock:(AudioEncodeDataBlock)encodeBlock {
    CFRetain(sampleBuffer);
    dispatch_async(_encoderQueue, ^{
        if (!_audioConverter) {
            [self setupEncoderFromSampleBuffer:sampleBuffer];
        }
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        CFRetain(blockBuffer);
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &_pcmBufferSize, &_pcmBuffer);
        NSError *error = nil;
        if (status != kCMBlockBufferNoErr) {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        memset(_aacBuffer, 0, _aacBufferSize);
        
        AudioBufferList outAudioBufferList = {0};
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        outAudioBufferList.mBuffers[0].mDataByteSize = (int)_aacBufferSize;
        outAudioBufferList.mBuffers[0].mData = _aacBuffer;
        AudioStreamPacketDescription *outPacketDescription = NULL;
        UInt32 ioOutputDataPacketSize = 1;
        // Converts data supplied by an input callback function, supporting non-interleaved and packetized formats.
        // Produces a buffer list of output data from an AudioConverter. The supplied input callback function is called whenever necessary.
        status = AudioConverterFillComplexBuffer(_audioConverter, inInputDataProcess, (__bridge void *)(self), &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
        NSData *data = nil;
        if (status == 0) {
            NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length channel:1];
            NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
            [fullData appendData:rawAAC];
            data = fullData;
        } else {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        if (encodeBlock) {
            dispatch_async(_callbackQueue, ^{
                encodeBlock(data);
            });
        }
        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    });
}

/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength channel:(int)channel {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 11;   //4;  //44.1KHz
    int chanCfg = channel;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF; // 11111111     = syncword
    packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

- (int)sampleRateIndex:(int)sampleRate {
    switch (sampleRate) {
        case 96000:
            return 0;
            break;
        case 88200:
            return 1;
            break;
        case 64000:
            return 2;
            break;
        case 48000:
            return 3;
            break;
        case 44100:
            return 4;
            break;
        case 32000:
            return 5;
            break;
        case 24000:
            return 6;
            break;
        case 22050:
            return 7;
            break;
        case 16000:
            return 8;
            break;
        case 12000:
            return 9;
            break;
        case 11025:
            return 10;
            break;
        case 8000:
            return 11;
            break;
        default:
            break;
    }
    return 4;
}

- (void) dealloc {
    AudioConverterDispose(_audioConverter);
    free(_aacBuffer);
    
    NSLog(@"dealloc AACEncoder +++++++++++++=");
}

@end
