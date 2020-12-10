//
//  ViewController.m
//  LiveShowCD
//
//  Created by mysoul on 2020/11/4.
//

#import "ViewController.h"
#import "MSCamPreviewView.h"
#import "MSVideoEncoder.h"
#import "MSVideoDecoder.h"
#import "AAPLEAGLLayer.h"

typedef NS_ENUM(NSUInteger, CameraSetupResult) {
    CameraSetupResultSuccess,
    CameraSetupResultNoAuthorized,
    CameraSetupResultFailed
};

#define SCREENWIDTH [UIScreen mainScreen].bounds.size.width
#define SCrEENHEIGHT [UIScreen mainScreen].bounds.size.height

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic) AVCaptureSession * captureSession;
@property (nonatomic) AVCaptureDeviceInput * videoDeviceInput;
@property (nonatomic) AVCaptureVideoDataOutput * videoDataOutput;

@property (nonatomic) AVCaptureAudioDataOutput * audioDataOutput;

@property (nonatomic) AVCaptureDeviceDiscoverySession * discoverySession;

@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) dispatch_queue_t outputQueue;

@property (nonatomic) CameraSetupResult cameraSetResult;

@property(nonatomic, strong)MSCamPreviewView * previewView;
@property(nonatomic, strong)MSVideoEncoder * videoEncoder;
@property(nonatomic, strong)MSVideoDecoder * videoDecoder;

@property(nonatomic, strong)NSFileHandle * fileHandle;
@property(nonatomic, strong)AAPLEAGLLayer * playLayer;
@end

@implementation ViewController
- (IBAction)cameraControl:(UIButton *)sender {
    sender.selected = !sender.isSelected;
    if (sender.isSelected) {
        [self.videoEncoder releaseCompressionSession];
        [self.captureSession stopRunning];
    } else {
        [self.captureSession startRunning];
    }
}

- (IBAction)contentModeChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) { // Aspect
        self.previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    } else if (sender.selectedSegmentIndex == 1) {                                // Fill
        self.previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    } else {
        self.previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravityResize;
    }
}

- (IBAction)videoQualityChanged:(UISegmentedControl *)sender {
    [self.captureSession stopRunning];
    
    [self.videoEncoder releaseCompressionSession];
    self.videoEncoder = nil;
    self.fileHandle = nil;
    
    [self.captureSession beginConfiguration];
    if (sender.selectedSegmentIndex == 0) {         // High
        self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    } else if (sender.selectedSegmentIndex == 1) {  // Medium
        self.captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    } else {                                        // Low
        self.captureSession.sessionPreset = AVCaptureSessionPresetLow;
    }
    [self.captureSession commitConfiguration];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.captureSession startRunning];
    });
}

- (void)focusPointTap:(UIGestureRecognizer *)gesture {
    CGPoint devicePoint = [self.previewView.videoPreviewLayer captureDevicePointOfInterestForPoint:[gesture locationInView:gesture.view]];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode
       exposeWithMode:(AVCaptureExposureMode)exposureMode
        atDevicePoint:(CGPoint)point
monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async(self.sessionQueue, ^{
        AVCaptureDevice* device = self.videoDeviceInput.device;
        NSError* error = nil;
        if ([device lockForConfiguration:&error]) {
            /*
             Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
             Call set(Focus/Exposure)Mode() to apply the new point of interest.
            */
            if (device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode]) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if (device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode]) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        }
        else {
            NSLog(@"Could not lock device for configuration: %@", error);
        }
    });
}

#pragma mark - 属性懒加载
- (MSVideoEncoder *)videoEncoder {
    if (!_videoEncoder) {
        __weak ViewController * selfWeak = self;
        _videoEncoder = [[MSVideoEncoder alloc] initWithEncodeVideoDataType:VideoDataTypeH264];
        _videoEncoder.ErrorBlock = ^(NSString * _Nullable error) {
            if (selfWeak.captureSession.isRunning) {
                [selfWeak.captureSession stopRunning];
            }
        };
    }
    return _videoEncoder;
}

- (MSVideoDecoder *)videoDecoder {
    if (!_videoDecoder) {
        __weak ViewController * selfWeak = self;
        _videoDecoder = [[MSVideoDecoder alloc] init];
        _videoDecoder.outputDataBlock = ^(CVPixelBufferRef pixelBuffer) {
            selfWeak.playLayer.pixelBuffer = pixelBuffer;
        };
    }
    return _videoDecoder;
}

- (NSFileHandle *)fileHandle{
    if (!_fileHandle) {
        NSString * filePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"test.hevc"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
        [[NSFileManager defaultManager] createFileAtPath:filePath contents:[NSData data] attributes:nil];
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    }
    return _fileHandle;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.cameraSetResult = CameraSetupResultSuccess;
    
    self.previewView = [[MSCamPreviewView alloc] initWithFrame:CGRectMake(0, 64, SCREENWIDTH, SCrEENHEIGHT-128)];
    self.previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view addSubview:self.previewView];
    [self.previewView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusPointTap:)]];
    
    self.playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(100, 100, SCREENWIDTH-100, (SCREENWIDTH-100)*667/375.0)];
    self.playLayer.backgroundColor = [UIColor blackColor].CGColor;
    [self.view.layer addSublayer:self.playLayer];
    
    // Create the capture session.
    AVCaptureSession * captureSession = [[AVCaptureSession alloc] init];
    self.captureSession = captureSession;
    
    self.previewView.captureSession = captureSession;
    
    NSArray * deviceTyps = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera];
    self.discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTyps mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    
    self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    self.outputQueue = dispatch_queue_create("output queue", DISPATCH_QUEUE_SERIAL);
    
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusAuthorized:
        {
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            // 挂起线程，请求相机权限
            dispatch_suspend(self.sessionQueue);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (!granted) {
                    self.cameraSetResult = CameraSetupResultFailed;
                } else {
                    self.cameraSetResult = CameraSetupResultNoAuthorized;
                }
                dispatch_resume(self.sessionQueue);
            }];
        }
            break;
        default:
        {
            self.cameraSetResult = CameraSetupResultNoAuthorized;;
        }
            break;
    }
    
    dispatch_async(self.sessionQueue, ^{
        if (self.cameraSetResult == CameraSetupResultSuccess) {
            [self configureSession];
        } else {
            NSLog(@"Failed to configure session, cause no authorized");
            self.cameraSetResult = CameraSetupResultFailed;
        }
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    dispatch_async(self.sessionQueue, ^{
        if (self.cameraSetResult == CameraSetupResultSuccess) {
            [self.captureSession startRunning];
        }
    });
}

- (void)configureSession {
    
    NSError * error = nil;
    
    [self.captureSession beginConfiguration];
    
    self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    
    // 获取摄像头设备
    AVCaptureDevice * videoDevice =
        [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
    if (!videoDevice) {
        videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        if (!videoDevice) {
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
        }
    }
    
    // 创建视频输入设备
    AVCaptureDeviceInput * videoDeviceInput =
        [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    self.videoDeviceInput = videoDeviceInput;
    
    if (videoDeviceInput) {
        // If the input can be added, add it to the session.
        if ([self.captureSession canAddInput:videoDeviceInput]) {
            [self.captureSession addInput:videoDeviceInput];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.previewView.videoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        });
    } else {
        // Configuration failed. Handle error.
        NSLog(@"Init video input error: %@", error.description);
        self.cameraSetResult = CameraSetupResultFailed;
    }
    
    // 创建音频输入设备
    AVCaptureDevice * audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput * audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    
    if ([self.captureSession canAddInput:audioInput]) {
        [self.captureSession addInput:audioInput];
    }
    
    if (error) {
        // Configuration failed. Handle error.
        NSLog(@"Init audio input error: %@", error.description);
        self.cameraSetResult = CameraSetupResultFailed;
    }
    
    // full {Height = 1080;PixelFormatType = 875704422;Width = 1920;}
    // video {Height = 1080;PixelFormatType = 875704438;Width = 1920;}
    
    // 创建视频输出设备
    AVCaptureVideoDataOutput * videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [videoOutput setVideoSettings:@{(__bridge id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];
    [videoOutput setSampleBufferDelegate:self queue:self.outputQueue];
    if ([self.captureSession canAddOutput:videoOutput]) {
        [self.captureSession addOutput:videoOutput];
    }
    self.videoDataOutput = videoOutput;
    
    AVCaptureConnection * connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    // 创建音频输出设备
//    AVCaptureAudioDataOutput * audioOutput = [[AVCaptureAudioDataOutput alloc] init];
//    [audioOutput setSampleBufferDelegate:self queue:self.outputQueue];
//    if ([self.captureSession canAddOutput:audioOutput]) {
//        [self.captureSession addOutput:audioOutput];
//    }
//    self.audioDataOutput = audioOutput;
    
    [self.captureSession commitConfiguration];
    
    NSLog(@"%@", videoOutput.videoSettings);
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([output isKindOfClass:NSClassFromString(@"AVCaptureVideoDataOutput")]) {
        NSLog(@"%@", [NSThread currentThread]);
        __weak ViewController * selfWeak = self;
        [self.videoEncoder encodeSampleBuffer:sampleBuffer outputData:^(NSData * _Nonnull data) {
//            [selfWeak.fileHandle writeData:data];
            [selfWeak.videoDecoder decodeVideoDataWithNaluData:data];
        }];
    } else if ([output isKindOfClass:NSClassFromString(@"AVCaptureAudioDataOutput")]) {
        NSLog(@"AVCaptureAudioDataOutput +++");
    }
}


@end
