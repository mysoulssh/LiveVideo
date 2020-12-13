//
//  MSVideoDecoder.m
//  LiveShowCD
//
//  Created by mysoul on 2020/12/7.
//

#import "MSVideoDecoder.h"

@interface MSVideoDecoder()
{
    int32_t _vpsSize;
    int32_t _spsSize;
    int32_t _ppsSize;
    
    uint8_t * _vps;
    uint8_t * _sps;
    uint8_t * _pps;
    
    CMVideoFormatDescriptionRef _videoFormatDescription;
}

@property(nonatomic, assign)VTDecompressionSessionRef decompressSession;
@property(nonatomic, assign)VideoDataType decodeVideoDataType;

@end

@implementation MSVideoDecoder

- (instancetype)initWithDecodeVideoDataType:(VideoDataType)decodeVideoDataType {
    if (self = [super init]) {
        if (@available(iOS 11.0, *)) {
            self.decodeVideoDataType = decodeVideoDataType;
        } else {
            self.decodeVideoDataType = VideoDataTypeH264;
        }
    }
    return self;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.decodeVideoDataType = VideoDataTypeH264;
    }
    return self;
}

#pragma mark - 解码器相关
- (void)decodeFrame:(void *)frame frameSize:(int32_t)frameSize{
    if (!self.decompressSession) {
        return;
    }
    CMBlockBufferRef blockBuffer = NULL;
    // 创建 CMBlockBufferRef
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                          (void *)frame,
                                                          frameSize,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameSize,
                                                          FALSE,
                                                          &blockBuffer);
    if(status != kCMBlockBufferNoErr) {
        return;
    }
    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSizeArray[] = {frameSize};
    // 创建 CMSampleBufferRef
    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                       blockBuffer,
                                       _videoFormatDescription,
                                       1, 0, NULL, 1, sampleSizeArray,
                                       &sampleBuffer);
    if (status != kCMBlockBufferNoErr || sampleBuffer == NULL) {
        return;
    }
    // VTDecodeFrameFlags 0为允许多线程解码
    VTDecodeFrameFlags flags = 0;
    VTDecodeInfoFlags flagOut = 0;
    // 解码 这里第四个参数会传到解码的callback里的sourceFrameRefCon，可为空
    CVPixelBufferRef outputPixelBuffer = NULL;
    OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(self.decompressSession,
                                                              sampleBuffer,
                                                              flags,
                                                              &outputPixelBuffer,
                                                              &flagOut);
    if (decodeStatus != noErr) {
        NSLog(@"decode frame error: %d", (int)decodeStatus);
    }
    // Create了就得Release
    CFRelease(sampleBuffer);
    CFRelease(blockBuffer);
}

- (void)decodeVideoDataWithNaluData:(NSData *)naluData {
    uint8_t *frame = (uint8_t *)naluData.bytes;
    uint32_t frameSize = (uint32_t)naluData.length;
    // frame的前4个字节是NALU数据的开始码，也就是00 00 00 01，
    // 第5个字节是表示数据类型，转为10进制后，7是sps, 8是pps, 5是IDR（I帧）信息
    int nalu_type = (frame[4] & 0x1F);

    // 将NALU的开始码转为4字节大端NALU的长度信息
    uint32_t nalSize = (uint32_t)(frameSize - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    frame[0] = *(pNalSize + 3);
    frame[1] = *(pNalSize + 2);
    frame[2] = *(pNalSize + 1);
    frame[3] = *(pNalSize);
    switch (nalu_type)
    {
        case 0x05: // I帧
            NSLog(@"NALU type is IDR frame");
            if([self initVideoDecoder])
            {
                [self decodeFrame:frame frameSize:frameSize];
            }
            break;
        case 0x07: // SPS
            NSLog(@"NALU type is SPS frame");
            _spsSize = frameSize - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        case 0x08: // PPS
            NSLog(@"NALU type is PPS frame");
            _ppsSize = frameSize - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        default: // B帧或P帧
            NSLog(@"NALU type is B/P frame");
            [self decodeFrame:frame frameSize:frameSize];
            break;
    }
}

- (VTDecompressionSessionRef)initVideoDecoder{
    if (self.decompressSession) {
        return self.decompressSession;
    }
    
    CMVideoFormatDescriptionRef videoFormatDesRef = NULL;
    OSStatus status = 0;
    if (self.decodeVideoDataType == VideoDataTypeHEVC) {
        const uint8_t* const parameterSetPointers[3] = {_vps, _sps, _pps};
        const size_t parameterSetSizes[3] = {_vpsSize, _spsSize, _ppsSize};
        
        if (@available(iOS 11.0, *)) {
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault, 3, parameterSetPointers, parameterSetSizes, 4, NULL, &videoFormatDesRef);
        }
    } else {
        const uint8_t* const parameterSetPointers[2] = {_sps, _pps};
        const size_t parameterSetSizes[2] = {_spsSize, _ppsSize};
        
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &videoFormatDesRef);
    }
    
    
    if (status != noErr) {
        NSLog(@"create decoder format error:%d", (int)status);
        return NULL;
    }
    _videoFormatDescription = videoFormatDesRef;
    
    // 从sps pps中获取解码视频的宽高信息
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(videoFormatDesRef);

    self.width = self.width?:dimensions.width;
    self.height = self.height?:dimensions.height;
    
    // kCVPixelBufferPixelFormatTypeKey 解码图像的采样格式
    // kCVPixelBufferWidthKey、kCVPixelBufferHeightKey 解码图像的宽高
    // kCVPixelBufferOpenGLCompatibilityKey制定支持OpenGL渲染，经测试有没有这个参数好像没什么差别
    NSDictionary* destinationPixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (id)kCVPixelBufferWidthKey : @(self.width),
        (id)kCVPixelBufferHeightKey : @(self.height),
        (id)kCVPixelBufferOpenGLCompatibilityKey : @(YES)
    };
    
    VTDecompressionOutputCallbackRecord callback;
    callback.decompressionOutputCallback = videoDecompressDataCallback;
    callback.decompressionOutputRefCon = (__bridge void*)self;
    
    VTDecompressionSessionRef decompressSessionRef;
    status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                          videoFormatDesRef,
                                          NULL,
                                          (__bridge CFDictionaryRef _Nullable)(destinationPixelBufferAttributes),
                                          &callback,
                                          &decompressSessionRef);
    if (status != noErr) {
        NSLog(@"decoder create error: %d", (int)status);
        return nil;
    }
    
    // 实时解码
    VTSessionSetProperty(decompressSessionRef, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    // 解码线程数
    VTSessionSetProperty(decompressSessionRef, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)@(1));
    self.decompressSession = decompressSessionRef;
    return self.decompressSession;
}

#pragma mark - Decode video data output
void videoDecompressDataCallback(void * CM_NULLABLE decompressionOutputRefCon,
                                 void * CM_NULLABLE sourceFrameRefCon,
                                 OSStatus status,
                                 VTDecodeInfoFlags infoFlags,
                                 CM_NULLABLE CVImageBufferRef imageBuffer,
                                 CMTime presentationTimeStamp,
                                 CMTime presentationDuration ){
    if (status != noErr) {
        NSLog(@"decode error: %d", (int)status);
        return;
    }
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
    
    MSVideoDecoder * decoder = (__bridge MSVideoDecoder*)decompressionOutputRefCon;
    if (decoder.outputDataBlock) {
        decoder.outputDataBlock(imageBuffer);
    }
    
    if (imageBuffer != NULL) {
        CVPixelBufferRelease(imageBuffer);
    }
}

- (void)dealloc {
    self.decompressSession = NULL;
}

@end
