//
//  AVCamPreviewView.m
//  LiveShowCD
//
//  Created by mysoul on 2020/11/6.
//

#import "MSCamPreviewView.h"

@implementation MSCamPreviewView

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureVideoPreviewLayer*) videoPreviewLayer
{
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (AVCaptureSession*) captureSession
{
    return self.videoPreviewLayer.session;
}

- (void)setCaptureSession:(AVCaptureSession*) captureSession
{
    self.videoPreviewLayer.session = captureSession;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
