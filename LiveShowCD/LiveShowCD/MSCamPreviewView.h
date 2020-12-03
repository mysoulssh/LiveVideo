//
//  AVCamPreviewView.h
//  LiveShowCD
//
//  Created by mysoul on 2020/11/6.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface MSCamPreviewView : UIView

@property (nonatomic, readonly) AVCaptureVideoPreviewLayer * videoPreviewLayer;

@property (nonatomic) AVCaptureSession * captureSession;

@end

NS_ASSUME_NONNULL_END
