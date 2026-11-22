//
//  HCNetSDKBridge.h
//  海康 HCNetSDK iOS 接入层（仅在 HAS_HIKSDK=1 时编译）
//
//  用法：从 open.hikvision.com 下载「设备网络SDK（iOS）」，
//        把 HCNetSDK.framework / libhcnetsdk.a + 头文件放进 HikMon/SDK/，
//        在 project.yml 里把 HAS_HIKSDK 改为 1，并加 framework 搜索路径。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HCNetSDKBridge : NSObject

+ (BOOL)sdkAvailable;
+ (NSString *)sdkVersion;
+ (void)globalInit;

/// 登录：返回 userId，-1 表示失败（错误码见 lastError）
+ (NSInteger)loginHost:(NSString *)host
                  port:(int)port
                  user:(NSString *)user
              password:(NSString *)pass;

+ (void)logout:(NSInteger)userId;

/// 实时预览：streamType 0=主码流 1=子码流
+ (NSInteger)startRealPlay:(NSInteger)userId
                   channel:(int)channel
                streamType:(int)streamType
                      view:(UIView *)view;

+ (void)stopRealPlay:(NSInteger)handle;

/// 回放：按时间起止（yyyy-MM-dd HH:mm:ss），streamType 同上
+ (NSInteger)startPlayback:(NSInteger)userId
                   channel:(int)channel
                 startTime:(NSString *)start
                   endTime:(NSString *)end
                      view:(UIView *)view;

+ (void)stopPlayback:(NSInteger)handle;
+ (void)playbackPause:(NSInteger)handle;
+ (void)playbackResume:(NSInteger)handle;
+ (void)playbackSeek:(NSInteger)handle seconds:(int)seconds;

/// 声音
+ (BOOL)openSound:(NSInteger)handle;
+ (BOOL)closeSound:(NSInteger)handle;

/// 对讲：开始/停止（SDK 内部采集麦克风）
+ (BOOL)startTalk:(NSInteger)userId;
+ (void)stopTalk;

/// 云台：cmd 见 SDK（1上 2下 3左 4右 11放大 12缩小…），stop=YES 表示松手停止
+ (BOOL)ptz:(NSInteger)userId channel:(int)channel cmd:(int)cmd stop:(BOOL)stop;

+ (NSString *)lastError;

@end

NS_ASSUME_NONNULL_END
