//
//  MSVideoEncoder.m
//  LiveShowCD
//
//  Created by mysoul on 2020/12/3.
//

#import "MSVideoEncoder.h"

#define BITRATE_BluRay 5120*1024
#define BITRATE_HD     2560*1024
#define BITRATE_SD     1920*1024
#define BITRATE_PC_360 1280*1024


@interface MSVideoEncoder()
@property(nonatomic, assign)VTCompressionSessionRef compressSession;
@property(nonatomic, copy)VideoEncodeDataBlock outputBlock;
@property(nonatomic, assign)int64_t frameID;
@property (nonatomic) CFStringRef encodeLevel;

@property (nonatomic) dispatch_queue_t encodeQueue;
@property(nonatomic, assign)VideoDataType encodeVideoDataType;
@end

@implementation MSVideoEncoder

- (instancetype)initWithEncodeVideoDataType:(VideoDataType)encodeVideDataType {
    if (self = [super init]) {
        if (@available(iOS 11.0, *)) {
            self.encodeVideoDataType = encodeVideDataType;
        } else {
            self.encodeVideoDataType = VideoDataTypeH264;
        }
        [self baseConfigure];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.encodeVideoDataType = VideoDataTypeH264;
        [self baseConfigure];
    }
    return self;
}

- (void)baseConfigure {
    self.fps = 30;
    self.bitRate = BITRATE_HD;
    self.keyFrameInterval = 60;
    self.limit = @[@(self.bitRate*1.5/8), @(1)];
    self.videoQuality = EncodeVideoQualityHD;
    self.encodeQueue = dispatch_queue_create("encodeQueue", DISPATCH_QUEUE_SERIAL);
    if (self.encodeVideoDataType == VideoDataTypeHEVC) {
        if (@available(iOS 11.0, *)) {
            self.encodeLevel = kVTProfileLevel_HEVC_Main_AutoLevel;
        }
    } else {
        self.encodeLevel = kVTProfileLevel_H264_Baseline_4_0;
    }
}

- (void)setEncodeVideoQuality:(EncodeVideoQuality)quality {
    if (self.videoQuality == quality) {
        return;
    }
    switch (quality) {
        case EncodeVideoQualityBluRay:
            self.bitRate = BITRATE_BluRay;
            self.encodeLevel = kVTProfileLevel_H264_Baseline_5_0;
            break;
        case EncodeVideoQualityHD:
            self.bitRate = BITRATE_HD;
            self.encodeLevel = kVTProfileLevel_H264_Baseline_4_0;
            break;
        case EncodeVideoQualitySD:
            self.bitRate = BITRATE_SD;
            self.encodeLevel = kVTProfileLevel_H264_Baseline_3_1;
            break;
        case EncodeVideoQualityPC_360:
            self.bitRate = BITRATE_PC_360;
            self.encodeLevel = kVTProfileLevel_H264_Baseline_1_3;
            break;
            
        default:
            break;
    }
    
    if (self.encodeVideoDataType == VideoDataTypeHEVC) {
        if (@available(iOS 11.0, *)) {
            self.encodeLevel = kVTProfileLevel_HEVC_Main_AutoLevel;
        } else {
            // Fallback on earlier versions
        }
    }
    
    self.limit = @[@(self.bitRate*1.5/8), @(1)];
    
    [self releaseCompressionSession];
}

#pragma mark - 编码器相关
// 将 sampleBuffer(摄像头捕捉数据,原始帧数据) 编码为H.264
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer outputData:(VideoEncodeDataBlock)block {
    if (![self initVideoEncoderWithSampleBuffer:sampleBuffer]) {
        return;
    }
    //  1.保存 block 块
    self.outputBlock = block;
    
    //  2.将sampleBuffer转成imageBuffer
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    //  3.根据当前的帧数,创建CMTime的时间
    CMTime presentationTimeStamp = CMTimeMake(self.frameID++, 1000);
    VTEncodeInfoFlags flags;
    
    //  4.开始编码该帧数据
    OSStatus statusCode = VTCompressionSessionEncodeFrame(
                                                          self.compressSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL,
                                                          (__bridge void * _Nullable)(self),
                                                          &flags
                                                          );
    
    if (statusCode != noErr) {
        NSString * err = [NSString stringWithFormat:@"VTCompressionSessionEncodeFrame failed with %d", (int)statusCode];
        NSLog(@"%@", err);
        VTCompressionSessionInvalidate(self.compressSession);
        CFRelease(self.compressSession);
        self.compressSession = NULL;
        if (self.ErrorBlock) {
            self.ErrorBlock(err);
        }
        return;
    }
}

- (VTCompressionSessionRef)initVideoEncoderWithSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (self.compressSession) {
        return self.compressSession;
    }
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    VTCompressionSessionRef compressSession;
    
    CMVideoCodecType codecType = self.encodeVideoDataType==VideoDataTypeHEVC?kCMVideoCodecType_HEVC:kCMVideoCodecType_H264;
    OSStatus status = VTCompressionSessionCreate(NULL,
                                                 (int32_t)width,
                                                 (int32_t)height,
                                                 codecType,
                                                 NULL,
                                                 NULL,
                                                 NULL,
                                                 videoCompressDataCallback,
                                                 (__bridge void * _Nullable)(self),
                                                 &compressSession);
    if (status != noErr) {
        NSLog(@"创建编码器失败!!! %d", (int)status);
        return nil;
    }
    
    // 设置实时编码输出（直播必然是实时输出,否则会有延迟）
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_ProfileLevel, self.encodeLevel);
    
    // 设置关键帧（GOPsize)间隔
    int frameInterval = self.keyFrameInterval*self.fps;
    CFNumberRef frameIntervalRef = CFNumberCreate(NULL, kCFNumberIntType, &frameInterval);
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    
    // 设置关键帧时间间隔
    int frameIntervalDuration = self.keyFrameInterval;
    CFNumberRef frameIntervalDurationRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &frameIntervalDuration);
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, frameIntervalDurationRef);
    
    // 设置期望帧率(每秒多少帧,如果帧率过低,会造成画面卡顿)
    int fps = self.fps;
    CFNumberRef fpsRef = CFNumberCreate(NULL, kCFNumberIntType, &fps);
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
    
    // 设置码率(码率: 编码效率, 码率越高,则画面越清晰, 如果码率较低会引起马赛克 --> 码率高有利于还原原始画面,但是也不利于传输)
    int32_t bitRate = self.bitRate?:1628*1024;
    CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
    
    // 不产生B帧
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    
    // 设置码率，均值，单位是byte 这是一个算法
    NSArray *limit = self.limit.count?self.limit:@[@(bitRate * 1.5/8), @(1)];
    VTSessionSetProperty(compressSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    
    // 基本设置结束, 准备进行编码
    status = VTCompressionSessionPrepareToEncodeFrames(compressSession);
    if (status != noErr) {
        NSLog(@"VTCompressionSessionPrepareToEncodeFrames error: %d", (int)status);
        return nil;
    }
    
    self.compressSession = compressSession;
    return self.compressSession;
}

#pragma mark - Encode video data output
void videoCompressDataCallback(void *outputCallbackRefCon,
                               void *sourceFrameRefCon,
                               OSStatus status,
                               VTEncodeInfoFlags infoFlags,
                               CMSampleBufferRef sampleBuffer) {
    // 1.判断状态是否等于没有错误
    if (status != noErr) {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompress data is not ready ");
        return;
    }
    
    // 2.根据传入的参数获取对象
    MSVideoEncoder* encoder = (__bridge MSVideoEncoder*)outputCallbackRefCon;
    
    // 3.判断是否是关键帧
    bool isKeyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    // 判断当前帧是否为关键帧
    if (encoder.encodeVideoDataType == VideoDataTypeHEVC) {
        // 获取vps sps & pps数据
        if (isKeyframe)
        {
            if (@available(iOS 11.0, *)) {
                // 获取编码后的信息（存储于CMFormatDescriptionRef中）
                CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
                
                int naluHeaderLength = 0;
                // 获取VPS信息
                size_t vparameterSetSize, vparameterSetCount;
                const uint8_t *vparameterSet;
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 0, &vparameterSet, &vparameterSetSize, &vparameterSetCount, &naluHeaderLength);
                
                
                // 获取SPS信息
                size_t sparameterSetSize, sparameterSetCount;
                const uint8_t *sparameterSet;
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 1, &sparameterSet, &sparameterSetSize, &sparameterSetCount, &naluHeaderLength);
                
                // 获取PPS信息
                size_t pparameterSetSize, pparameterSetCount;
                const uint8_t *pparameterSet;
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 2, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &naluHeaderLength);
                
                // 将vps,sps/pps转成NSData
                NSData *vps = [NSData dataWithBytes:vparameterSet length:vparameterSetSize];
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                
                // 写入文件
                [encoder gotVpsSpsPps:vps sps:sps pps:pps];
            }
        }
    } else {
        // 获取sps & pps数据
        if (isKeyframe)
        {
            // 获取编码后的信息（存储于CMFormatDescriptionRef中）
            CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
            
            // 获取SPS信息
            size_t sparameterSetSize, sparameterSetCount;
            const uint8_t *sparameterSet;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
            
            // 获取PPS信息
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            
            // 将sps/pps转成NSData
            NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
            NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
            
            // 写入文件
            [encoder gotSpsPps:sps pps:pps];
        }
    }
    
    // 获取数据块
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder gotEncodedData:data isKeyFrame:isKeyframe];
            
            // 移动到写一个块，转成NALU单元
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
    
    NSLog(@"encode block %@", [NSThread currentThread]);
}

// 获取 sps 以及 pps,并进行StartCode
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps{
    
    // 拼接NALU的 StartCode,默认规定使用 00000001
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];

    NSMutableData *videoEncodeData = [[NSMutableData alloc] init];
    [videoEncodeData appendData:ByteHeader];
    [videoEncodeData appendData:sps];
    if (self.outputBlock) {
        self.outputBlock(videoEncodeData);
    }
    
    [videoEncodeData resetBytesInRange:NSMakeRange(0, [videoEncodeData length])];
    [videoEncodeData setLength:0];
    [videoEncodeData appendData:ByteHeader];
    [videoEncodeData appendData:pps];
    if (self.outputBlock) {
        self.outputBlock(videoEncodeData);
    }
}

// 获取 vps, sps 以及 pps,并进行StartCode
- (void)gotVpsSpsPps:(NSData *)vps sps:(NSData*)sps pps:(NSData*)pps{
    
    // 拼接NALU的 StartCode,默认规定使用 00000001
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    NSMutableData *videoEncodeData = [[NSMutableData alloc] init];
    [videoEncodeData appendData:ByteHeader];
    [videoEncodeData appendData:vps];
    if (self.outputBlock) {
        self.outputBlock(videoEncodeData);
    }

    [videoEncodeData resetBytesInRange:NSMakeRange(0, [videoEncodeData length])];
    [videoEncodeData setLength:0];
    [videoEncodeData appendData:ByteHeader];
    [videoEncodeData appendData:sps];
    if (self.outputBlock) {
        self.outputBlock(videoEncodeData);
    }
    
    [videoEncodeData resetBytesInRange:NSMakeRange(0, [videoEncodeData length])];
    [videoEncodeData setLength:0];
    [videoEncodeData appendData:ByteHeader];
    [videoEncodeData appendData:pps];
    if (self.outputBlock) {
        self.outputBlock(videoEncodeData);
    }
}

- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame{
    
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;     //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    NSMutableData *videoEncodeData = [[NSMutableData alloc] init];
    [videoEncodeData appendData:ByteHeader];
    [videoEncodeData appendData:data];
    if (self.outputBlock) {
        self.outputBlock(videoEncodeData);
    }
}

#pragma mark - Dealloc video encoder
- (void)releaseCompressionSession {
    NSLog(@"release block %@", [NSThread currentThread]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.compressSession) {
            VTCompressionSessionInvalidate(self.compressSession);
            CFRelease(self.compressSession);
            self.compressSession = NULL;
        }
    });
}

@end
