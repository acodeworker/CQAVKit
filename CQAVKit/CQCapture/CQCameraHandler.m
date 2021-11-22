//
//  CQCameraHandler.m
//  CQAVKit
//
//  Created by 刘超群 on 2021/10/29.
//

#import "CQCameraHandler.h"
#import <AVFoundation/AVFoundation.h>


static const NSString *CameraAdjustingExposureContext;

@interface CQCameraHandler ()
@property (nonatomic, strong) dispatch_queue_t videoQueue; ///< 视频队列
@property (nonatomic, strong) AVCaptureSession *captureSession; ///< 捕捉会话
/// captureSession下活跃的视频输入,一个捕捉会话下会有很多，设置个成员变量方便拿
@property (nonatomic, strong) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic, strong) AVCaptureStillImageOutput *imageOutput;  ///< 图片输出
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;  ///< 电影输出
@property (nonatomic, strong) NSURL *outputURL;  ///< 输出URL
@end

@implementation CQCameraHandler

#pragma mark - Func 设置会话
// 设置会话，设置分辨率，并将输入输出添加到会话中
- (BOOL)setupSession:(NSError * _Nullable *)error {
    // 创建捕捉会话 AVCaptureSession 是捕捉场景的中心枢纽
    self.captureSession = [[AVCaptureSession alloc] init];
    
    /*
     AVCaptureSessionPresetHigh
     AVCaptureSessionPresetMedium
     AVCaptureSessionPresetLow
     AVCaptureSessionPreset640x480
     AVCaptureSessionPreset1280x720
     AVCaptureSessionPresetPhoto
     */
    // 设置图像分辨率
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    
    // 设置视频音频输入
    // 添加视频捕捉设备
    // 拿到默认视频捕捉设备 iOS默认后置摄像头
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    // 将捕捉设备转化为AVCaptureDeviceInput
    // 注意：会话不能直接使用AVCaptureDevice，必须将AVCaptureDevice封装成AVCaptureDeviceInput对象
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error];
    // 将捕捉设备添加给会话
    // 使用前判断videoInput是否有效以及能否添加，因为摄像头是一个公共设备，不属于任何App，有可能别的App在使用，添加前应该先进行判断是否可以添加
    if (videoInput && [self.captureSession canAddInput:videoInput]) {
        // 将videoInput 添加到 captureSession中
        [self.captureSession addInput:videoInput];
        self.videoDeviceInput = videoInput;
    }else {
        return NO;
    }
    
    // 添加音频捕捉设备
    // 选择默认音频捕捉设备 即返回一个内置麦克风
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:error];
    if (audioInput && [self.captureSession canAddInput:audioInput]) {
        [self.captureSession addInput:audioInput];
    }else {
        return NO;
    }

    // 设置输出(图片/视频)
    // AVCaptureStillImageOutput 从摄像头捕捉静态图片
    self.imageOutput = [[AVCaptureStillImageOutput alloc] init];
    // 配置字典：希望捕捉到JPEG格式的图片
    self.imageOutput.outputSettings = @{AVVideoCodecKey:AVVideoCodecJPEG};
    // 输出连接 判断是否可用，可用则添加到输出连接中去
    if ([self.captureSession canAddOutput:self.imageOutput]) {
        [self.captureSession addOutput:self.imageOutput];
    }
    // AVCaptureMovieFileOutput，将QuickTime视频录制到文件系统
    self.movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([self.captureSession canAddOutput:self.movieOutput]) {
        [self.captureSession addOutput:self.movieOutput];
    }
    
    return YES;
}

// 开始会话
- (void)startSession {
    // 检查是否处于运行状态
    if (![self.captureSession isRunning]) {
        // 使用同步调用会损耗一定的时间，则用异步的方式处理
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

// 停止会话
- (void)stopSession {
    // 检查是否处于运行状态
    if ([self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }
}

#pragma mark - Func 镜头切换
/// 根据position拿到摄像头
- (AVCaptureDevice *)getCameraWithPosition:(AVCaptureDevicePosition)position {
    NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

/// 获取当前活跃的摄像头
- (AVCaptureDevice *)getActiveCamera {
    return self.videoDeviceInput.device;
}

/// 获取未激活的摄像头
- (AVCaptureDevice *)getInactiveCamera {
    // 通过查找当前激活摄像头的反向摄像头获得，如果设备只有1个摄像头，则返回nil
    AVCaptureDevice *device = nil;
    if (self.cameraCount > 1) {
        if ([self getActiveCamera].position == AVCaptureDevicePositionBack) {
            device = [self getCameraWithPosition:AVCaptureDevicePositionFront];
        } else {
            device = [self getCameraWithPosition:AVCaptureDevicePositionBack];
        }
    }
    return device; 
}

// 切换摄像头
- (BOOL)switchCamera {
    if (![self canSwitchCamera]) return NO;
    
    // 获取当前设备的反向设备
    AVCaptureDevice *inactiveCamera = [self getInactiveCamera];
    // 将输入设备封装成AVCaptureDeviceInput
    NSError *error;
    AVCaptureDeviceInput *newVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:inactiveCamera error:&error];
    
    if (newVideoInput != nil) {
        // 开始配置 标注原始配置要发生改变
        [self.captureSession beginConfiguration];
        // TODO: 是不是移除了才能加新的？
        // FIXME: 是不是移除了才能加新的？
        // 将捕捉会话中，原本的捕捉输入设备移除
        [self.captureSession removeInput:self.videoDeviceInput];
        if ([self.captureSession canAddInput:newVideoInput]) {
            [self.captureSession addInput:newVideoInput];
            self.videoDeviceInput = newVideoInput;
        } else {
            // !!!: 是不是要给个回调？
            // ???: 是不是要给个回调？
            // 已经移除了，还是无法添加新设备，则将原本的视频捕捉设备重新加入到捕捉会话中
            [self.captureSession addInput:self.videoDeviceInput];
        }
        // 提交配置，AVCaptureSession commitConfiguration 会分批的将所有变更整合在一起。
        [self.captureSession commitConfiguration];
        return YES;
    } else {
        // 创建AVCaptureDeviceInput 出现错误，回调该错误
        [self.delegate deviceConfigurationFailedWithError:error];
        return NO;
    }
}

// 是否能切换摄像头
- (BOOL)canSwitchCamera {
    return self.cameraCount > 1;
}

- (NSUInteger)cameraCount {
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

#pragma mark - Func 对焦&曝光

/**
 AVCaptureDevice定义了很多方法，让开发者控制ios设备上的摄像头。可以独立调整和锁定摄像头的焦距、曝光、白平衡。对焦和曝光可以基于特定的兴趣点进行设置，使其在应用中实现点击对焦、点击曝光的功能。
 还可以让你控制设备的LED作为拍照的闪光灯或手电筒的使用。
 每当修改摄像头设备时，一定要先测试修改动作是否能被设备支持。并不是所有的摄像头都支持所有功能，例如部分设备前置摄像头就不支持对焦操作，因为它和目标距离一般在一臂之长的距离。但大部分后置摄像头是可以支持全尺寸对焦。尝试应用一个不被支持的动作，会导致异常崩溃。所以修改摄像头设备前，需要判断是否支持
 */

- (BOOL)isSupportsExposeWithCamera:(AVCaptureDevice *)camera {
    // 摄像头是否支持兴趣点曝光
    return camera.isExposurePointOfInterestSupported;
}

// 设置对焦点
- (void)focusAtPoint:(CGPoint)point {
    AVCaptureDevice *device = [self getActiveCamera];
    // 摄像头是否支持兴趣点对焦 & 是否支持自动对焦模式 ,不支持不操作，玩手动对焦的需求另说
    if (!device.isFocusPointOfInterestSupported || ![device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) return;
    NSError *error;
    // 锁定设备准备配置
    if ([device lockForConfiguration:&error]) {
        // 设置对焦点
        device.focusPointOfInterest = point;
        // 对焦模式设置为自动对焦
        device.focusMode = AVCaptureFocusModeAutoFocus;
        // 释放锁定
        [device unlockForConfiguration];
    } else {
        // 锁定错误时，回调错误处理代理
        [self.delegate deviceConfigurationFailedWithError:error];
    }
}


// 设置曝光点
- (void)exposeAtPoint:(CGPoint)point {
    AVCaptureDevice *device = [self getActiveCamera];
    // 摄像头是否支持兴趣点曝光 & 是否支持自动曝光模式 ,不支持不操作，玩手动曝光的需求另说
    if (!device.isExposurePointOfInterestSupported || ![device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) return;
    NSError *error;
    // 锁定设备准备配置
    if ([device lockForConfiguration:&error]) {
        // 设置曝光点
        device.exposurePointOfInterest = point;
        // 曝光模式设置为自动曝光
        device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        //判断设备是否支持锁定曝光的模式。
        if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
            //支持，则使用kvo确定设备的adjustingExposure属性的状态。
            [device addObserver:self forKeyPath:@"adjustingExposure" options:NSKeyValueObservingOptionNew context:&CameraAdjustingExposureContext];
        }
        // 释放锁定
        [device unlockForConfiguration];
    } else {
        // 锁定错误时，回调错误处理代理
        [self.delegate deviceConfigurationFailedWithError:error];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == &CameraAdjustingExposureContext) {
        //获取device
        AVCaptureDevice *device = (AVCaptureDevice *)object;
    }
}

// 重置对焦和曝光
- (void)resetFocusAndExposureModes {
    
}

#pragma mark - Func 图片&视频捕捉


// 捕捉静态图片
- (void)captureStillImage {
    
}

// 开始录制视频
- (void)startRecordingVideo {
    
}

// 停止录制视频
- (void)stopRecordingVideo {
    
}

// 是否在录制视频
- (BOOL)isRecordingVideo {
    return YES;
}

// 录制视频的时间
- (CMTime)recordedDuration {
    return kCMTimeZero;
}

#pragma mark - Lazy Load
- (dispatch_queue_t)videoQueue {
    if (!_videoQueue) {
        _videoQueue = dispatch_queue_create("CQ_VideoQueue", NULL);
    }
    return _videoQueue;
}

@end
