//
//  HikMonSDK.h
//  海康 HCNetSDK (iOS) 的 Objective-C 门面。
//  这个头文件是唯一进 bridging header 的 SDK 头，不含任何 HCNetSDK 结构体/宏。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HikMonSDK : NSObject

// MARK: - 全局
+ (BOOL)available;
+ (NSString *)sdkVersion;
+ (void)globalInit;
+ (unsigned int)lastErrorCode;
+ (NSString *)lastErrorText;
+ (nullable NSString *)resolveHost:(NSString *)host;

/// 码流加密验证码（NET_DVR_SetSDKLocalConfig.byProtectKey），登录前调用
+ (BOOL)setProtectKey:(NSString *)key;

// MARK: - 登录 / 会话
+ (NSInteger)loginHost:(NSString *)host
                  port:(int)port
                  user:(NSString *)user
              password:(NSString *)pass;
+ (void)logout:(NSInteger)userId;
+ (int)channelCount:(NSInteger)userId;
+ (int)channelBase:(NSInteger)userId;

// MARK: - 实时预览（SDK 自渲染到 UIView）
+ (NSInteger)startRealPlay:(NSInteger)userId
                   channel:(int)channel
                 subStream:(BOOL)subStream
                      view:(UIView *)view;
+ (void)stopRealPlay:(NSInteger)handle;
+ (BOOL)makeKeyFrame:(NSInteger)userId channel:(int)channel;

// MARK: - 声音
+ (BOOL)openSound:(NSInteger)handle;
+ (BOOL)closeSound;
+ (BOOL)setVolume:(NSInteger)handle volume:(int)volume;

// MARK: - 语音对讲（MR_V30 + 数据回调）
/// onData: 设备端回传的 G.711 帧；flag 为 SDK 的 byAudioFlag
+ (NSInteger)startVoiceCom:(NSInteger)userId
                   channel:(int)channel
                    onData:(void (^_Nullable)(NSData *data, int flag))onData;
+ (BOOL)sendVoiceData:(NSInteger)handle data:(NSData *)data;
+ (void)stopVoiceCom:(NSInteger)handle;

// MARK: - 回放
+ (NSInteger)startPlayback:(NSInteger)userId
                   channel:(int)channel
                      from:(NSDate *)from
                        to:(NSDate *)to
                      view:(UIView *)view;
+ (void)stopPlayback:(NSInteger)handle;
+ (BOOL)playbackPause:(NSInteger)handle;
+ (BOOL)playbackResume:(NSInteger)handle;
+ (BOOL)playbackFast:(NSInteger)handle;
+ (BOOL)playbackNormal:(NSInteger)handle;
+ (int)playbackPositionMillisecond:(NSInteger)handle;
+ (int)playbackTotalMillisecond:(NSInteger)handle;

// MARK: - ISAPI（NET_DVR_STDXMLConfig 透传，只读诊断用）
/// url 形如 "GET /ISAPI/System/deviceInfo"；body 为 POST 时的 XML，可传 nil
+ (NSString *)stdXML:(NSInteger)userId
                 url:(NSString *)url
                body:(nullable NSString *)body
              status:(NSString *_Nullable *_Nullable)statusOut;

@end

NS_ASSUME_NONNULL_END
