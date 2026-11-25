//
//  HikMonSDK.mm  (Objective-C++)
//  海康 HCNetSDK iOS 静态库的真实调用层。
//
//  编译开关：GCC_PREPROCESSOR_DEFINITIONS 里有 HAS_HIKSDK=1 时走真实现，
//  否则整个文件退化成空实现，保证没有 SDK 也能编译。
//
//  关键点（都是踩过的坑）：
//  1) HCNetSDK.h 在 __APPLE__ 下把 NET_DVR_API 定义成 extern "C"，只能在 C++ 里
//     编译，所以本文件必须是 .mm。
//  2) HCNetSDK.h 会 #define BOOL int / #define NULL 0 / #define TRUE 1，
//     所以它必须放在 Foundation / UIKit 之后 include，且不能进 Swift 桥接头。
//  3) PlayM4 的官方头 plaympeg4.h 引用了 Windows 的 SYSTEMTIME，iOS 上编不过；
//     这里只手写用到的几个 PlayM4 声明（C linkage 与库中符号一致）。
//  4) NET_DVR_CloseSound() 没有参数；NET_DVR_StopVoiceCom() 要传句柄。
//

#import "HikMonSDK.h"

#import <netdb.h>
#import <arpa/inet.h>
#import <sys/socket.h>

#if HAS_HIKSDK

#include "HCNetSDK.h"

// ---------------------------------------------------------------------------
// PlayM4（libplayctrl.a / libHCCore.a）最小声明
// ---------------------------------------------------------------------------
extern "C" {
    BOOL  PlayM4_GetPort(LONG *nPort);
    BOOL  PlayM4_FreePort(LONG nPort);
    BOOL  PlayM4_SetStreamOpenMode(LONG nPort, DWORD nMode);
    BOOL  PlayM4_OpenStream(LONG nPort, BYTE *pFileHeadBuf, DWORD nSize, DWORD nBufPoolSize);
    BOOL  PlayM4_InputData(LONG nPort, BYTE *pBuf, DWORD nSize);
    BOOL  PlayM4_CloseStream(LONG nPort);
    BOOL  PlayM4_Play(LONG nPort, HWND hWnd);
    BOOL  PlayM4_Stop(LONG nPort);
    BOOL  PlayM4_PlaySound(LONG nPort);
    BOOL  PlayM4_StopSound(void);
    BOOL  PlayM4_SetDisplayBuf(LONG nPort, DWORD nNum);
    DWORD PlayM4_GetLastError(LONG nPort);
}

#define HIK_STREAME_REALTIME 0   // plaympeg4.h: STREAME_REALTIME
#define HIK_STREAME_FILE     1

// ---------------------------------------------------------------------------
// 回放上下文
// ---------------------------------------------------------------------------
@interface HikPlayCtx : NSObject
@property (atomic, assign) LONG  playHandle;
@property (atomic, assign) LONG  port;
@property (atomic, assign) BOOL  portReady;
@property (atomic, assign) int   totalMs;
@property (atomic, weak)   UIView *view;
@end

@implementation HikPlayCtx
@end

static NSMutableDictionary<NSNumber *, HikPlayCtx *> *gPlayCtxs = nil;
static NSMutableDictionary<NSNumber *, NSNumber *> *gChanCounts = nil;
static LONG gLiveSoundHandle = -1;
static LONG gTalkHandle = -1;

static void HikCtxInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gPlayCtxs = [NSMutableDictionary dictionary];
    });
}

static HikPlayCtx *HikCtxFor(LONG handle) {
    if (!gPlayCtxs) return nil;
    HikPlayCtx *ctx = nil;
    @synchronized (gPlayCtxs) {
        ctx = gPlayCtxs[@(handle)];
    }
    return ctx;
}

// 回放数据回调：SDK 在内部线程回调，这里只做搬运，UI 操作回主线程。
static void CALLBACK HikPlayDataCB(LONG lPlayHandle, DWORD dwDataType, BYTE *pBuffer,
                                   DWORD dwBufSize, DWORD dwUser)
{
    @autoreleasepool {
        HikPlayCtx *ctx = HikCtxFor(lPlayHandle);
        if (ctx == nil) return;

        if (dwDataType == NET_DVR_SYSHEAD) {
            if (ctx.portReady) return;
            LONG port = -1;
            if (!PlayM4_GetPort(&port)) {
                NSLog(@"[HikMonSDK] PlayM4_GetPort failed err=%u (handle=%d)",
                      (unsigned)PlayM4_GetLastError(port), (int)lPlayHandle);
                return;
            }
            PlayM4_SetStreamOpenMode(port, HIK_STREAME_REALTIME);
            // 有的固件第一个 SYSHEAD 包长为 0，也必须 OpenStream，否则后面 InputData 全部失败
            if (!PlayM4_OpenStream(port, dwBufSize > 0 ? pBuffer : NULL, dwBufSize, 4 * 1024 * 1024)) {
                NSLog(@"[HikMonSDK] PlayM4_OpenStream failed err=%u (head=%u)",
                      (unsigned)PlayM4_GetLastError(port), (unsigned)dwBufSize);
                PlayM4_FreePort(port);
                return;
            }
            ctx.port = port;
            ctx.portReady = YES;
            PlayM4_SetDisplayBuf(port, 1);

            UIView *v = ctx.view;
            LONG p = port;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (v.window != nil || v.superview != nil) {
                    if (!PlayM4_Play(p, (__bridge void *)v)) {
                        NSLog(@"[HikMonSDK] PlayM4_Play failed err=%u", (unsigned)PlayM4_GetLastError(p));
                    }
                }
                PlayM4_PlaySound(p);
            });
        } else if (dwDataType == NET_DVR_STREAMDATA || dwDataType == NET_DVR_AUDIOSTREAMDATA) {
            if (ctx.portReady && dwBufSize > 0) {
                // 缓冲满时 InputData 会返回失败，丢掉这帧继续喂即可
                PlayM4_InputData(ctx.port, pBuffer, dwBufSize);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------
static void HikFillTime(NET_DVR_TIME *t, NSDate *date) {
    if (t == NULL) return;
    memset(t, 0, sizeof(NET_DVR_TIME));
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone localTimeZone];
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                          NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                  fromDate:(date ?: [NSDate date])];
    t->dwYear   = (DWORD)c.year;
    t->dwMonth  = (DWORD)c.month;
    t->dwDay    = (DWORD)c.day;
    t->dwHour   = (DWORD)c.hour;
    t->dwMinute = (DWORD)c.minute;
    t->dwSecond = (DWORD)c.second;
}

static NSString *HikErrText(DWORD code) {
    NSString *meaning = @"";
    switch (code) {
        case 0:   meaning = @"成功"; break;
        case 1:   meaning = @"用户名密码错误"; break;
        case 2:   meaning = @"权限不足"; break;
        case 3:   meaning = @"SDK 未初始化"; break;
        case 4:   meaning = @"通道号错误"; break;
        case 5:   meaning = @"资源不足（句柄/端口用满）"; break;
        case 6:   meaning = @"句柄无效"; break;
        case 7:   meaning = @"连接设备失败（IP/端口不对或被防火墙拦）"; break;
        case 8:   meaning = @"向设备发送失败"; break;
        case 9:   meaning = @"从设备接收失败"; break;
        case 10:  meaning = @"解码失败"; break;
        case 12:  meaning = @"设备不在线"; break;
        case 29:  meaning = @"设备命令执行失败"; break;
        case 43:  meaning = @"设备不支持该操作"; break;
        case 96:  meaning = @"网络断开"; break;
        default:  meaning = @"SDK 错误"; break;
    }
    return [NSString stringWithFormat:@"错误码 %u（%@）", (unsigned)code, meaning];
}

@implementation HikMonSDK

+ (BOOL)available { return YES; }

+ (void)globalInit {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NET_DVR_Init();
        NET_DVR_SetConnectTime(3000, 3);
        NET_DVR_SetReconnect(10000, TRUE);
        HikCtxInit();
    });
}

+ (NSString *)sdkVersion {
    DWORD v = NET_DVR_GetSDKBuildVersion();
    return [NSString stringWithFormat:@"%X.%X.%X.%X (%u)",
            (unsigned)((v >> 24) & 0xFF), (unsigned)((v >> 16) & 0xFF),
            (unsigned)((v >> 8) & 0xFF), (unsigned)(v & 0xFF), (unsigned)v];
}

+ (unsigned int)lastErrorCode {
    return (unsigned int)NET_DVR_GetLastError();
}

+ (NSString *)lastErrorText {
    return HikErrText(NET_DVR_GetLastError());
}

+ (NSString *)resolveHost:(NSString *)host {
    if (host.length == 0) return nil;
    // 已经是 IPv4 就直接返回
    struct in_addr addr;
    if (inet_pton(AF_INET, host.UTF8String, &addr) == 1) return host;

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *res = NULL;
    if (getaddrinfo(host.UTF8String, NULL, &hints, &res) != 0 || res == NULL) return nil;

    char buf[INET_ADDRSTRLEN] = {0};
    NSString *ip = nil;
    for (struct addrinfo *p = res; p != NULL; p = p->ai_next) {
        if (p->ai_family == AF_INET) {
            struct sockaddr_in *sin = (struct sockaddr_in *)p->ai_addr;
            if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) {
                ip = [NSString stringWithUTF8String:buf];
                break;
            }
        }
    }
    freeaddrinfo(res);
    return ip;
}

// ---------------------------------------------------------------------------
// 登录
// ---------------------------------------------------------------------------
+ (NSInteger)loginHost:(NSString *)host port:(int)port user:(NSString *)user password:(NSString *)pass {
    [self globalInit];
    if (host.length == 0) return -1;

    NET_DVR_USER_LOGIN_INFO info;
    memset(&info, 0, sizeof(info));
    strncpy(info.sDeviceAddress, host.UTF8String, sizeof(info.sDeviceAddress) - 1);
    info.wPort = (WORD)(port > 0 ? port : 8000);
    strncpy(info.sUserName, (user ?: @"admin").UTF8String, sizeof(info.sUserName) - 1);
    strncpy(info.sPassword, (pass ?: @"").UTF8String, sizeof(info.sPassword) - 1);
    info.bUseAsynLogin = 0;
    info.byLoginMode = 0;      // 0 = Private（私有协议）
    info.byUseTransport = 0;
    info.byHttps = 0;

    NET_DVR_DEVICEINFO_V40 devInfo;
    memset(&devInfo, 0, sizeof(devInfo));

    LONG uid = NET_DVR_Login_V40(&info, &devInfo);
    if (uid < 0) {
        NSLog(@"[HikMonSDK] login %@:%d failed: %@", host, port, [self lastErrorText]);
        return -1;
    }

    int chans = (int)devInfo.struDeviceV30.byChanNum
              + (int)devInfo.struDeviceV30.byIPChanNum
              + (int)devInfo.struDeviceV30.byHighDChanNum * 256;
    if (chans <= 0) chans = (int)devInfo.struDeviceV30.byChanNum;
    @synchronized ([HikMonSDK class]) {
        if (gChanCounts == nil) gChanCounts = [NSMutableDictionary dictionary];
        gChanCounts[@(uid)] = @(chans);
    }
    NSLog(@"[HikMonSDK] login ok uid=%d chans=%d", (int)uid, chans);
    return (NSInteger)uid;
}

+ (void)logout:(NSInteger)userId {
    if (userId < 0) return;
    NET_DVR_Logout((LONG)userId);
    @synchronized ([HikMonSDK class]) {
        [gChanCounts removeObjectForKey:@(userId)];
    }
}

+ (int)channelCount:(NSInteger)userId {
    int n = 0;
    @synchronized ([HikMonSDK class]) {
        n = [gChanCounts[@(userId)] intValue];
    }
    return n > 0 ? n : 1;
}

// ---------------------------------------------------------------------------
// 实时预览
// ---------------------------------------------------------------------------
+ (NSInteger)startRealPlay:(NSInteger)userId channel:(int)channel subStream:(BOOL)subStream view:(UIView *)view {
    [self globalInit];
    if (userId < 0 || view == nil) return -1;

    NET_DVR_PREVIEWINFO pi;
    memset(&pi, 0, sizeof(pi));
    pi.lChannel       = (LONG)(channel > 0 ? channel : 1);
    pi.dwStreamType   = (DWORD)(subStream ? 1 : 0);   // 0 主码流 / 1 子码流
    pi.dwLinkMode     = 0;                            // 0 = TCP
    pi.hPlayWnd       = (__bridge void *)view;
    pi.bBlocked       = 0;   // 0 = 非阻塞取流，4 宫格一起开不会卡住主线程
    pi.byProtoType    = 0;                            // 私有协议
    pi.dwDisplayBufNum = 1;

    LONG h = NET_DVR_RealPlay_V40((LONG)userId, &pi, NULL, NULL);
    if (h < 0) {
        NSLog(@"[HikMonSDK] RealPlay ch%d failed: %@", channel, [self lastErrorText]);
        return -1;
    }
    return (NSInteger)h;
}

+ (void)stopRealPlay:(NSInteger)handle {
    if (handle < 0) return;
    if (gLiveSoundHandle == (LONG)handle) {
        NET_DVR_CloseSound();
        gLiveSoundHandle = -1;
    }
    NET_DVR_StopRealPlay((LONG)handle);
}

// ---------------------------------------------------------------------------
// 声音 / 对讲
// ---------------------------------------------------------------------------
+ (BOOL)openSound:(NSInteger)handle {
    if (handle < 0) return NO;
    BOOL ok = NET_DVR_OpenSound((LONG)handle);
    if (ok) gLiveSoundHandle = (LONG)handle;
    return ok ? YES : NO;
}

+ (BOOL)closeSound {
    BOOL ok = NET_DVR_CloseSound();
    gLiveSoundHandle = -1;
    return ok ? YES : NO;
}

+ (BOOL)setVolume:(NSInteger)handle volume:(int)volume {
    if (handle < 0) return NO;
    int v = volume < 0 ? 0 : (volume > 100 ? 100 : volume);
    return NET_DVR_Volume((LONG)handle, (WORD)v) ? YES : NO;
}

+ (NSInteger)startVoiceTalk:(NSInteger)userId channel:(int)channel {
    if (userId < 0) return -1;
    if (gTalkHandle >= 0) {
        NET_DVR_StopVoiceCom(gTalkHandle);
        gTalkHandle = -1;
    }
    LONG h = NET_DVR_StartVoiceCom_V30((LONG)userId, (DWORD)(channel > 0 ? channel : 1), 0, NULL, NULL);
    if (h < 0) {
        NSLog(@"[HikMonSDK] StartVoiceCom failed: %@", [self lastErrorText]);
        return -1;
    }
    gTalkHandle = h;
    return (NSInteger)h;
}

+ (void)stopVoiceTalk:(NSInteger)talkHandle {
    LONG h = (talkHandle >= 0) ? (LONG)talkHandle : gTalkHandle;
    if (h >= 0) {
        NET_DVR_StopVoiceCom(h);
    }
    gTalkHandle = -1;
}

// ---------------------------------------------------------------------------
// 云台
// ---------------------------------------------------------------------------
+ (BOOL)ptzControl:(NSInteger)userId channel:(int)channel command:(int)command stop:(BOOL)stop {
    if (userId < 0) return NO;
    return NET_DVR_PTZControl_Other((LONG)userId, (LONG)(channel > 0 ? channel : 1),
                                    (DWORD)command, stop ? 1 : 0) ? YES : NO;
}

// ---------------------------------------------------------------------------
// 回放
// ---------------------------------------------------------------------------
+ (NSInteger)startPlayback:(NSInteger)userId channel:(int)channel from:(NSDate *)from to:(NSDate *)to view:(UIView *)view {
    [self globalInit];
    if (userId < 0 || view == nil) return -1;
    HikCtxInit();

    NET_DVR_VOD_PARA para;
    memset(&para, 0, sizeof(para));
    para.dwSize = sizeof(NET_DVR_VOD_PARA);
    para.struIDInfo.dwSize = sizeof(NET_DVR_STREAM_INFO);
    para.struIDInfo.dwChannel = (DWORD)(channel > 0 ? channel : 1);
    HikFillTime(&para.struBeginTime, from);
    HikFillTime(&para.struEndTime, to);
    para.hWnd = NULL;            // 外部解码（走数据回调 + PlayM4）
    para.byDrawFrame = 0;
    para.byStreamType = 0;       // 主码流

    LONG h = NET_DVR_PlayBackByTime_V40((LONG)userId, &para);
    if (h < 0) {
        NSLog(@"[HikMonSDK] PlayBackByTime_V40 failed: %@", [self lastErrorText]);
        return -1;
    }

    HikPlayCtx *ctx = [[HikPlayCtx alloc] init];
    ctx.playHandle = h;
    ctx.port = -1;
    ctx.portReady = NO;
    ctx.view = view;
    ctx.totalMs = (int)([to timeIntervalSinceDate:from] * 1000.0);
    @synchronized (gPlayCtxs) {
        gPlayCtxs[@(h)] = ctx;
    }

    if (!NET_DVR_SetPlayDataCallBack(h, HikPlayDataCB, (DWORD)h)) {
        NSLog(@"[HikMonSDK] SetPlayDataCallBack failed: %@", [self lastErrorText]);
        [self stopPlayback:(NSInteger)h];
        return -1;
    }

    if (!NET_DVR_PlayBackControl(h, NET_DVR_PLAYSTART, 0, NULL)) {
        NSLog(@"[HikMonSDK] PLAYSTART failed: %@", [self lastErrorText]);
        [self stopPlayback:(NSInteger)h];
        return -1;
    }
    return (NSInteger)h;
}

+ (void)stopPlayback:(NSInteger)handle {
    if (handle < 0) return;
    HikPlayCtx *ctx = HikCtxFor((LONG)handle);
    if (ctx) {
        LONG port = ctx.port;
        BOOL ready = ctx.portReady;
        ctx.portReady = NO;
        @synchronized (gPlayCtxs) {
            [gPlayCtxs removeObjectForKey:@(handle)];
        }
        NET_DVR_StopPlayBack((LONG)handle);
        if (ready && port >= 0) {
            PlayM4_Stop(port);
            PlayM4_StopSound();
            PlayM4_CloseStream(port);
            PlayM4_FreePort(port);
        }
    } else {
        NET_DVR_StopPlayBack((LONG)handle);
    }
}

+ (BOOL)playbackPause:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYPAUSE, 0, NULL) ? YES : NO;
}

+ (BOOL)playbackResume:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYRESTART, 0, NULL) ? YES : NO;
}

+ (BOOL)playbackSeek:(NSInteger)handle toMillisecond:(int)ms {
    if (handle < 0) return NO;
    DWORD in = (DWORD)(ms < 0 ? 0 : ms);
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYSETPOS, in, NULL) ? YES : NO;
}

+ (int)playbackPositionMillisecond:(NSInteger)handle {
    if (handle < 0) return 0;
    DWORD out = 0;
    if (!NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYGETTIME, 0, &out)) return 0;
    return (int)out;
}

+ (int)playbackTotalMillisecond:(NSInteger)handle {
    if (handle < 0) return 0;
    return HikCtxFor((LONG)handle).totalMs;
}

@end

#else   // HAS_HIKSDK == 0 —— 空实现，保证工程在没放 SDK 时也能编过

@implementation HikMonSDK
+ (BOOL)available { return NO; }
+ (NSString *)sdkVersion { return @"未集成"; }
+ (void)globalInit {}
+ (unsigned int)lastErrorCode { return 0; }
+ (NSString *)lastErrorText { return @"未集成 HCNetSDK"; }
+ (NSString *)resolveHost:(NSString *)host { return host; }
+ (NSInteger)loginHost:(NSString *)h port:(int)p user:(NSString *)u password:(NSString *)pw { return -1; }
+ (void)logout:(NSInteger)userId {}
+ (int)channelCount:(NSInteger)userId { return 1; }
+ (NSInteger)startRealPlay:(NSInteger)userId channel:(int)c subStream:(BOOL)s view:(UIView *)v { return -1; }
+ (void)stopRealPlay:(NSInteger)handle {}
+ (BOOL)openSound:(NSInteger)handle { return NO; }
+ (BOOL)closeSound { return NO; }
+ (BOOL)setVolume:(NSInteger)handle volume:(int)volume { return NO; }
+ (NSInteger)startVoiceTalk:(NSInteger)userId channel:(int)c { return -1; }
+ (void)stopVoiceTalk:(NSInteger)talkHandle {}
+ (BOOL)ptzControl:(NSInteger)userId channel:(int)c command:(int)cmd stop:(BOOL)stop { return NO; }
+ (NSInteger)startPlayback:(NSInteger)userId channel:(int)c from:(NSDate *)f to:(NSDate *)t view:(UIView *)v { return -1; }
+ (void)stopPlayback:(NSInteger)handle {}
+ (BOOL)playbackPause:(NSInteger)handle { return NO; }
+ (BOOL)playbackResume:(NSInteger)handle { return NO; }
+ (BOOL)playbackSeek:(NSInteger)handle toMillisecond:(int)ms { return NO; }
+ (int)playbackPositionMillisecond:(NSInteger)handle { return 0; }
+ (int)playbackTotalMillisecond:(NSInteger)handle { return 0; }
@end

#endif
