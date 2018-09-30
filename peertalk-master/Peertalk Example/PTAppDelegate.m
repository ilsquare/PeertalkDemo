#import "PTAppDelegate.h"
#import "PTUSBHub.h"
#import "PTExampleProtocol.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>


@interface PTAppDelegate () <AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>{
  // If the remote connection is over USB transport...
  NSNumber *connectingToDeviceID_;
  NSNumber *connectedDeviceID_;
  NSDictionary *connectedDeviceProperties_;
  NSDictionary *remoteDeviceInfo_;
  dispatch_queue_t notConnectedQueue_;
  BOOL notConnectedQueueSuspended_;
  PTChannel *connectedChannel_;
  NSDictionary *consoleTextAttributes_;
  NSDictionary *consoleStatusTextAttributes_;
  NSMutableDictionary *pings_;
}

@property (readonly) NSNumber *connectedDeviceID;
@property PTChannel *connectedChannel;
@property (nonatomic, strong)   AVCaptureSession            *avSession;
@property (nonatomic , strong)  AVCaptureVideoDataOutput    *videoOutput; //

- (void)presentMessage:(NSString*)message isStatus:(BOOL)isStatus;
- (void)startListeningForDevices;
- (void)didDisconnectFromDevice:(NSNumber*)deviceID;
- (void)disconnectFromCurrentChannel;
- (void)enqueueConnectToLocalIPv4Port;
- (void)connectToLocalIPv4Port;
- (void)connectToUSBDevice;
- (void)ping;

@end


@implementation PTAppDelegate

@synthesize window = window_;
@synthesize inputTextField = inputTextField_;
@synthesize outputTextView = outputTextView_;
@synthesize connectedDeviceID = connectedDeviceID_;


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  // We use a serial queue that we toggle depending on if we are connected or
  // not. When we are not connected to a peer, the queue is running to handle
  // "connect" tries. When we are connected to a peer, the queue is suspended
  // thus no longer trying to connect.
  notConnectedQueue_ = dispatch_queue_create("PTExample.notConnectedQueue", DISPATCH_QUEUE_SERIAL);
  
  // Configure the output NSTextView we use for UI feedback
  outputTextView_.textContainerInset = NSMakeSize(15.0, 10.0);
  consoleTextAttributes_ = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSFont fontWithName:@"helvetica" size:16.0], NSFontAttributeName,
                            [NSColor lightGrayColor], NSForegroundColorAttributeName,
                            nil];
  consoleStatusTextAttributes_ = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSFont fontWithName:@"menlo" size:11.0], NSFontAttributeName,
                                  [NSColor darkGrayColor], NSForegroundColorAttributeName,
                                  nil];
  
  // Configure the input NSTextField we use for UI input
  [inputTextField_ setFont:[NSFont fontWithDescriptor:[[consoleTextAttributes_ objectForKey:NSFontAttributeName] fontDescriptor] size:14.0]];
  [self.window makeFirstResponder:inputTextField_];
  
  // Start listening for device attached/detached notifications
  [self startListeningForDevices];
  
  // Start trying to connect to local IPv4 port (defined in PTExampleProtocol.h)
  [self enqueueConnectToLocalIPv4Port];
  
  // Put a little message in the UI
  [self presentMessage:@"Ready for action — connecting at will." isStatus:YES];
  
  // Start pinging
  [self ping];
    
    [self startCapture];
    
}
#pragma mark - AVCapture-输出流-Delegate

// 默认情况下，为30 fps，意味着该函数每秒调用30次
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // 获取输入设备数据，有可能是音频有可能是视频
    if (captureOutput == self.videoOutput) {
        //捕获到视频数据
        //         YUV422转YUV420
//        CVPixelBufferRef pixelBuf_After = [self processYUV422ToYUV420WithSampleBuffer:sampleBuffer];
        CVImageBufferRef pixelBuffer_Before = CMSampleBufferGetImageBuffer(sampleBuffer);

        size_t width = CVPixelBufferGetWidth(pixelBuffer_Before);
        
        size_t height  = CVPixelBufferGetHeight(pixelBuffer_Before);
        
        unsigned char* buffer = (unsigned char*) malloc(width * height * 1.5);
        
        // 取视频YUV数据
        
        [self copyDataFromYUVPixelBuffer:pixelBuffer_Before toBuffer:buffer];
        
        // 保存到本地
        
        NSData *retData = [NSData dataWithBytes:buffer length:sizeof(unsigned char)*(width*height*1.5)];
        
        free(buffer);
        
        buffer = nil;

        
        // 当TCP需要开始传输数据时，开始编码
        
        dispatch_data_t payload = PTExampleTextDispatchDataWithData(retData);
        [connectedChannel_ sendFrameOfType:PTExampleFrameTypeTextMessage tag:PTFrameNoTag withPayload:payload callback:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to send message: %@", error);
            }
        }];

        
    }
    else
    {
        // 音频
        /*
         mediaType:'soun'
         mediaSubType:'lpcm'
         */
        //        NSLog(@"--- 音频 ----");
    }
}

- (void) copyDataFromYUVPixelBuffer:(CVPixelBufferRef)pixelBuffer toBuffer:(unsigned char*)buffer {
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    if (CVPixelBufferIsPlanar(pixelBuffer)) {
        
        size_t w = CVPixelBufferGetWidth(pixelBuffer);
        
        size_t h = CVPixelBufferGetHeight(pixelBuffer);
        
        size_t d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        
        unsigned char* src = (unsigned char*) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        
        unsigned char* dst = buffer;
        
        for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += w, src += d) {
            
            memcpy(dst, src, w);
            
        }
        
        d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        
        src = (unsigned char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        h = h >> 1;
        w = w >> 1;
        
        for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += w, src += d) {
            
            memcpy(dst, src, w);
            
        }
        
        d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 2);
        
        src = (unsigned char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2);
        
        for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += w, src += d) {
            
            memcpy(dst, src, w);
            
        }
        
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}


#pragma mark - 懒加载
-(AVCaptureSession *)avSession
{
    if (!_avSession) {
        
        _avSession = [[AVCaptureSession alloc] init];
        _avSession.sessionPreset = AVCaptureSessionPreset1280x720;
        /*
         sessionPreset为AVCaptureSessionPresetHigh，可不显式指定；      为什么设置成什么值都没有反应？
         AVCaptureSessionPreset320x240
         AVCaptureSessionPreset640x480,
         AVCaptureSessionPreset960x540
         AVCaptureSessionPreset1280x720
         */
        
        // 设备对象 (audio)
        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        // 输入流
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
        // 输出流
        AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
        [audioOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
        // 添加输入输出流
        if ([_avSession canAddInput:audioInput]) {
            [_avSession addInput:audioInput];
        }
        if ([_avSession canAddOutput:audioOutput]) {
            [_avSession addOutput:audioOutput];
        }
        
        
        
        
        // 设备对象 (video)
        AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        
        // 输入流
        AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        
        // 输出流
        self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        [self.videoOutput setAlwaysDiscardsLateVideoFrames:NO];
        //        [self.videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        
        // 帧的大小在这里设置才有效
        self.videoOutput.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8Planar], kCVPixelBufferPixelFormatTypeKey,
                                          [NSNumber numberWithInt: 960], (id)kCVPixelBufferWidthKey,
                                          [NSNumber numberWithInt: 540], (id)kCVPixelBufferHeightKey,
                                          nil];
        /*
         调用次数       CVBytesPerRow
         kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;      （420f）                       1924
         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ;      420v                        1924            964
         kCVPixelFormatType_422YpCbCr8_yuvs;                    yuvs            30          2560
         kCVPixelFormatType_422YpCbCr8                          2vuy            30          2560
         */
        [self.videoOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
        
        
        
        
        
        // 获取当前设备支持的像素格式
        //        NSLog(@"-- videoDevice.formats = %@", videoDevice.formats);
        
        //根据设备输出获得连接
        AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
        
        
        
        // 摄像头翻转
        connection.videoMirrored = YES;
        
        if ([_avSession canAddInput:videoInput]) {
            [_avSession addInput:videoInput];
        }
        if ([_avSession canAddOutput:self.videoOutput]) {
            [_avSession addOutput:self.videoOutput];
        }
        
        
        
    }
    return _avSession;
}


-(void)startCapture
{
    [self.avSession startRunning];
}


- (IBAction)sendMessage:(id)sender {
  if (connectedChannel_) {
    NSString *message = self.inputTextField.stringValue;
    dispatch_data_t payload = PTExampleTextDispatchDataWithString(message);
    [connectedChannel_ sendFrameOfType:PTExampleFrameTypeTextMessage tag:PTFrameNoTag withPayload:payload callback:^(NSError *error) {
      if (error) {
        NSLog(@"Failed to send message: %@", error);
      }
    }];
    [self presentMessage:[NSString stringWithFormat:@"[you]: %@", message] isStatus:NO];
    self.inputTextField.stringValue = @"";
  }
}


- (void)presentMessage:(NSString*)message isStatus:(BOOL)isStatus {
  NSLog(@">> %@", message);
  [self.outputTextView.textStorage beginEditing];
  if (self.outputTextView.textStorage.length > 0) {
    message = [@"\n" stringByAppendingString:message];
  }
  [self.outputTextView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:message attributes:isStatus ? consoleStatusTextAttributes_ : consoleTextAttributes_]];
  [self.outputTextView.textStorage endEditing];
  
  [NSAnimationContext beginGrouping];
  [NSAnimationContext currentContext].duration = 0.15;
  [NSAnimationContext currentContext].timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  NSClipView* clipView = [[self.outputTextView enclosingScrollView] contentView];
  NSPoint newOrigin = clipView.bounds.origin;
  newOrigin.y += 5.0; // hack A 1/2
  [clipView setBoundsOrigin:newOrigin]; // hack A 2/2
  newOrigin.y += 1000.0;
  newOrigin = [clipView constrainScrollPoint:newOrigin];
  [clipView.animator setBoundsOrigin:newOrigin];
  [NSAnimationContext endGrouping];
  
  // Scrolling w/o animation:
  //[self.outputTextView scrollToEndOfDocument:self];
}


- (PTChannel*)connectedChannel {
  return connectedChannel_;
}

- (void)setConnectedChannel:(PTChannel*)connectedChannel {
  connectedChannel_ = connectedChannel;
  
  // Toggle the notConnectedQueue_ depending on if we are connected or not
  if (!connectedChannel_ && notConnectedQueueSuspended_) {
    dispatch_resume(notConnectedQueue_);
    notConnectedQueueSuspended_ = NO;
  } else if (connectedChannel_ && !notConnectedQueueSuspended_) {
    dispatch_suspend(notConnectedQueue_);
    notConnectedQueueSuspended_ = YES;
  }
  
  if (!connectedChannel_ && connectingToDeviceID_) {
    [self enqueueConnectToUSBDevice];
  }
}


#pragma mark - Ping


- (void)pongWithTag:(uint32_t)tagno error:(NSError*)error {
  NSNumber *tag = [NSNumber numberWithUnsignedInt:tagno];
  NSMutableDictionary *pingInfo = [pings_ objectForKey:tag];
  if (pingInfo) {
    NSDate *now = [NSDate date];
    [pingInfo setObject:now forKey:@"date ended"];
    [pings_ removeObjectForKey:tag];
    NSLog(@"Ping total roundtrip time: %.3f ms", [now timeIntervalSinceDate:[pingInfo objectForKey:@"date created"]]*1000.0);
  }
}


- (void)ping {
  if (connectedChannel_) {
    if (!pings_) {
      pings_ = [NSMutableDictionary dictionary];
    }
    uint32_t tagno = [connectedChannel_.protocol newTag];
    NSNumber *tag = [NSNumber numberWithUnsignedInt:tagno];
    NSMutableDictionary *pingInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSDate date], @"date created", nil];
    [pings_ setObject:pingInfo forKey:tag];
    [connectedChannel_ sendFrameOfType:PTExampleFrameTypePing tag:tagno withPayload:nil callback:^(NSError *error) {
      [self performSelector:@selector(ping) withObject:nil afterDelay:1.0];
      [pingInfo setObject:[NSDate date] forKey:@"date sent"];
      if (error) {
        [pings_ removeObjectForKey:tag];
      }
    }];
  } else {
    [self performSelector:@selector(ping) withObject:nil afterDelay:1.0];
  }
}


#pragma mark - PTChannelDelegate


- (BOOL)ioFrameChannel:(PTChannel*)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
  if (   type != PTExampleFrameTypeDeviceInfo
      && type != PTExampleFrameTypeTextMessage
      && type != PTExampleFrameTypePing
      && type != PTExampleFrameTypePong
      && type != PTFrameTypeEndOfStream) {
    NSLog(@"Unexpected frame of type %u", type);
    [channel close];
    return NO;
  } else {
    return YES;
  }
}

- (void)ioFrameChannel:(PTChannel*)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(PTData*)payload {
  //NSLog(@"received %@, %u, %u, %@", channel, type, tag, payload);
  if (type == PTExampleFrameTypeDeviceInfo) {
    NSDictionary *deviceInfo = [NSDictionary dictionaryWithContentsOfDispatchData:payload.dispatchData];
    [self presentMessage:[NSString stringWithFormat:@"Connected to %@", deviceInfo.description] isStatus:YES];
  } else if (type == PTExampleFrameTypeTextMessage) {
    PTExampleTextFrame *textFrame = (PTExampleTextFrame*)payload.data;
    textFrame->length = ntohl(textFrame->length);
    NSString *message = [[NSString alloc] initWithBytes:textFrame->utf8text length:textFrame->length encoding:NSUTF8StringEncoding];
    [self presentMessage:[NSString stringWithFormat:@"[%@]: %@", channel.userInfo, message] isStatus:NO];
  } else if (type == PTExampleFrameTypePong) {
    [self pongWithTag:tag error:nil];
  }
}

- (void)ioFrameChannel:(PTChannel*)channel didEndWithError:(NSError*)error {
  if (connectedDeviceID_ && [connectedDeviceID_ isEqualToNumber:channel.userInfo]) {
    [self didDisconnectFromDevice:connectedDeviceID_];
  }
  
  if (connectedChannel_ == channel) {
    [self presentMessage:[NSString stringWithFormat:@"Disconnected from %@", channel.userInfo] isStatus:YES];
    self.connectedChannel = nil;
  }
}


#pragma mark - Wired device connections


- (void)startListeningForDevices {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  
  [nc addObserverForName:PTUSBDeviceDidAttachNotification object:PTUSBHub.sharedHub queue:nil usingBlock:^(NSNotification *note) {
    NSNumber *deviceID = [note.userInfo objectForKey:@"DeviceID"];
    //NSLog(@"PTUSBDeviceDidAttachNotification: %@", note.userInfo);
    NSLog(@"PTUSBDeviceDidAttachNotification: %@", deviceID);

    dispatch_async(notConnectedQueue_, ^{
      if (!connectingToDeviceID_ || ![deviceID isEqualToNumber:connectingToDeviceID_]) {
        [self disconnectFromCurrentChannel];
        connectingToDeviceID_ = deviceID;
        connectedDeviceProperties_ = [note.userInfo objectForKey:@"Properties"];
        [self enqueueConnectToUSBDevice];
      }
    });
  }];
  
  [nc addObserverForName:PTUSBDeviceDidDetachNotification object:PTUSBHub.sharedHub queue:nil usingBlock:^(NSNotification *note) {
    NSNumber *deviceID = [note.userInfo objectForKey:@"DeviceID"];
    //NSLog(@"PTUSBDeviceDidDetachNotification: %@", note.userInfo);
    NSLog(@"PTUSBDeviceDidDetachNotification: %@", deviceID);
    
    if ([connectingToDeviceID_ isEqualToNumber:deviceID]) {
      connectedDeviceProperties_ = nil;
      connectingToDeviceID_ = nil;
      if (connectedChannel_) {
        [connectedChannel_ close];
      }
    }
  }];
}


- (void)didDisconnectFromDevice:(NSNumber*)deviceID {
  NSLog(@"Disconnected from device");
  if ([connectedDeviceID_ isEqualToNumber:deviceID]) {
    [self willChangeValueForKey:@"connectedDeviceID"];
    connectedDeviceID_ = nil;
    [self didChangeValueForKey:@"connectedDeviceID"];
  }
}


- (void)disconnectFromCurrentChannel {
  if (connectedDeviceID_ && connectedChannel_) {
    [connectedChannel_ close];
    self.connectedChannel = nil;
  }
}


- (void)enqueueConnectToLocalIPv4Port {
  dispatch_async(notConnectedQueue_, ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      [self connectToLocalIPv4Port];
    });
  });
}


- (void)connectToLocalIPv4Port {
  PTChannel *channel = [PTChannel channelWithDelegate:self];
  channel.userInfo = [NSString stringWithFormat:@"127.0.0.1:%d", PTExampleProtocolIPv4PortNumber];
  [channel connectToPort:PTExampleProtocolIPv4PortNumber IPv4Address:INADDR_LOOPBACK callback:^(NSError *error, PTAddress *address) {
    if (error) {
      if (error.domain == NSPOSIXErrorDomain && (error.code == ECONNREFUSED || error.code == ETIMEDOUT)) {
        // this is an expected state
      } else {
        NSLog(@"Failed to connect to 127.0.0.1:%d: %@", PTExampleProtocolIPv4PortNumber, error);
      }
    } else {
      [self disconnectFromCurrentChannel];
      self.connectedChannel = channel;
      channel.userInfo = address;
      NSLog(@"Connected to %@", address);
    }
    [self performSelector:@selector(enqueueConnectToLocalIPv4Port) withObject:nil afterDelay:PTAppReconnectDelay];
  }];
}


- (void)enqueueConnectToUSBDevice {
  dispatch_async(notConnectedQueue_, ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      [self connectToUSBDevice];
    });
  });
}


- (void)connectToUSBDevice {
  PTChannel *channel = [PTChannel channelWithDelegate:self];
  channel.userInfo = connectingToDeviceID_;
  channel.delegate = self;
  
  [channel connectToPort:PTExampleProtocolIPv4PortNumber overUSBHub:PTUSBHub.sharedHub deviceID:connectingToDeviceID_ callback:^(NSError *error) {
    if (error) {
      if (error.domain == PTUSBHubErrorDomain && error.code == PTUSBHubErrorConnectionRefused) {
        NSLog(@"Failed to connect to device #%@: %@", channel.userInfo, error);
      } else {
        NSLog(@"Failed to connect to device #%@: %@", channel.userInfo, error);
      }
      if (channel.userInfo == connectingToDeviceID_) {
        [self performSelector:@selector(enqueueConnectToUSBDevice) withObject:nil afterDelay:PTAppReconnectDelay];
      }
    } else {
      connectedDeviceID_ = connectingToDeviceID_;
      self.connectedChannel = channel;
      //NSLog(@"Connected to device #%@\n%@", connectingToDeviceID_, connectedDeviceProperties_);
      //infoTextField_.stringValue = [NSString stringWithFormat:@"Connected to device #%@\n%@", deviceID, connectedDeviceProperties_];
    }
  }];
}

@end
