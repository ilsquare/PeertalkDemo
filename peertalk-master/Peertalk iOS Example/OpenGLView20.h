//
//  OpenGLView20.h
//  MyTest
//
//  Created by smy  on 12/20/11.
//  Copyright (c) 2011 ZY.SYM. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/EAGL.h>
#include <sys/time.h>
#include <pthread.h>
//#include "libavcodec/avcodec.h"

@interface OpenGLView20 : UIView
{
	/** 
	 OpenGL绘图上下文
	 */
    EAGLContext             *_glContext; 
	
	/** 
	 帧缓冲区
	 */
    GLuint                  _framebuffer; 
	
	/** 
	 渲染缓冲区
	 */
    GLuint                  _renderBuffer; 
	
	/** 
	 着色器句柄
	 */
    GLuint                  _program;  
	
	/** 
	 YUV纹理数组
	 */
    GLuint                  _textureYUV[3]; 
	
	/** 
	 视频宽度
	 */
    GLuint                  _videoW;  
	
	/** 
	 视频高度
	 */
    GLuint                  _videoH;
    
    GLuint videoW1,videoW2,videoW3,videoW4;
    GLuint videoH1,videoH2,videoH3,videoH4;
    
    GLsizei                 _viewScale;
	   
    //void                    *_pYuvData;
    
    pthread_mutex_t  yuvMut;             // 互斥锁
    
#ifdef DEBUG
    struct timeval      _time;
    NSInteger           _frameRate;
#endif
}
#pragma mark - 接口
//- (void)displayYUV420pData:(AVFrame *)data width:(int)w height:(int)h;
- (void)displayYUV420pHardData:(void *)data width:(int)w height:(int)h;
/** 
 清除画面
 */
- (void)clearFrame;

@end
