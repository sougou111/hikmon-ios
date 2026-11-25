//
//  HikMonSDK.h
//  海康 HCNetSDK (iOS) 的 Objective-C 门面。
//
//  设计约束：
//  - 这个头文件是唯一进 bridging header 的 SDK 头，里面不出现任何 HCNetSDK 的
//    结构体 / 宏（HCNetSDK.h 会 #define BOOL int、#define NULL 0，绝对不能进
//    Swift 桥接头）。
//  - 真正的 SDK 调用全在 HikMonSDK.mm（Objective-C++）里，因为 HCNetSDK.h 在
//    __APPLE__ 分支下用的是 extern "C"，只能在 C++ 里编译。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HikMonSDK : NSObject

// MARK: - 全局

/// SDK 是否被编译进来（HAS_HIKSDK=1 时为 YES）
+ (BOOL)available;

/// 例如 "6.1.11.5 (20151204)"
+ (NSString *)sdkVersion;

/// NET_DVR_Init + 连接超时 / 重连参数，幂等
+ (void)globalInit;

/// 最近一次 NET_DVR_GetLastError 的原始码
+ (unsigned int)lastErrorCode;

/// "错误码 7（连接设备失败）"
+ (NSString *)lastErrorText;

/// 域名 -> IP，解析不出来返回 nil
+ (nullable NSString *)resolveHost:(NSString *)host;

// MARK: - 登录 / 会话

/// 返回 userId，<0 表示失败（详情看 lastErrorText）
+ (NSInteger)loginHost:(NSString *)host
                  port:(int)port
                  user:(NSString *)user
              password:(NSString *)pass;

+ (void)logout:(NSInteger)userId;

/// 登录返回的设备信息里解析出来的通道总数
+ (int)channelCount:(NSInteger)userId;

// MARK: - 实时预览（SDK 自渲染到 UIView）

+ (NSInteger)startRealPlay:(NSInteger)userId
                   channel:(int)channel
                 subStream:(BOOL)subStream
                      view:(UIView *)view;

+ (void)stopRealPlay:(NSInteger)handle;

// MARK: - 声音 / 对讲

/// NET_DVR_OpenSound(lRealHandle)
+ (BOOL)openSound:(NSInteger)handle;
/// NET_DVR_CloseSound()  —— 注意 SDK 这个接口没有参数
+ (BOOL)closeSound;
+ (BOOL)setVolume:(NSInteger)handle volume:(int)volume;

/// 返回对讲句柄，<0 失败
+ (NSInteger)startVoiceTalk:(NSInteger)userId channel:(int)channel;
/// NET_DVR_StopVoiceCom(lVoiceComHandle) —— 传句柄，不是 0
+ (void)stopVoiceTalk:(NSInteger)talkHandle;

// MARK: - 云台

/// command 用 SDK 原始值（1 上 / 2 下 / 3 左 / 4 右 / 11 放大 / 12 缩小…）
+ (BOOL)ptzControl:(NSInteger)userId channel:(int)channel command:(int)command stop:(BOOL)stop;

// MARK: - 回放（PlayBackByTime_V40 + 数据回调 + PlayM4 解码到 UIView）

+ (NSInteger)startPlayback:(NSInteger)userId
                   channel:(int)channel
                      from:(NSDate *)from
                        to:(NSDate *)to
                      view:(UIView *)view;

+ (void)stopPlayback:(NSInteger)handle;
+ (BOOL)playbackPause:(NSInteger)handle;
+ (BOOL)playbackResume:(NSInteger)handle;
+ (BOOL)playbackSeek:(NSInteger)handle toMillisecond:(int)ms;
+ (int)playbackPositionMillisecond:(NSInteger)handle;
+ (int)playbackTotalMillisecond:(NSInteger)handle;

@end

NS_ASSUME_NONNULL_END
