//
//  MSDefineHeader.h
//  LiveShowCD
//
//  Created by mysoul on 2020/12/7.
//

#ifndef MSDefineHeader_h
#define MSDefineHeader_h

#import <VideoToolbox/VideoToolbox.h>

typedef void (^VideoEncodeDataBlock)(NSData * data);
typedef void (^VideoDecodeDataBlock)(CVPixelBufferRef pixelBuffer);

typedef NS_ENUM(NSUInteger, EncodeVideoQuality) {
    EncodeVideoQualityBluRay,   // 1920 x 1080
    EncodeVideoQualityHD,       // 1280 x 720
    EncodeVideoQualitySD,       // 640 x 480
    EncodeVideoQualityPC_360    // 480 x 360
};

typedef NS_ENUM(NSUInteger, DecodeVideoQuality) {
    DecodeVideoQualityBluRay,   // 1920 x 1080
    DecodeVideoQualityHD,       // 1280 x 720
    DecodeVideoQualitySD,       // 640 x 480
    DecodeVideoQualityPC_360    // 480 x 360
};

typedef NS_ENUM(NSUInteger, VideoDataType) {
    VideoDataTypeH264,          // H264
    VideoDataTypeHEVC,          // HEVC
    VideoDataTypeMP4,           // MP4
    VideoDataTypeTS,            // TS
    VideoDataTypeFLV            // FLV
};

typedef NS_ENUM(NSUInteger, AudioDataType) {
    AudioDataTypePCM,           // PCM
    AudioDataTypeAAC,           // AAC
    AudioDataTypeOpus,          // OPUS
    AudioDataTypeU_Law,         // G711u
    AudioDataTypeA_Luw,         // G711a
};


#endif /* MSDefineHeader_h */
