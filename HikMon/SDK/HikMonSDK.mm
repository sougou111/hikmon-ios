//
//  HikMonSDK.mm  (Objective-C++)
//  海康 HCNetSDK iOS 静态库的真实调用层。
//
//  HAS_HIKSDK=1 走真实现，否则整文件退化成空实现，保证没 SDK 也能编过。
//

#import "HikMonSDK.h"

#import <netdb.h>
#import <arpa/inet.h>
#import <sys/socket.h>

#if HAS_HIKSDK

#include "HCNetSDK.h"

// ---------------------------------------------------------------------------
// PlayM4 最小声明（官方 plaympeg4.h 依赖 Windows 的 SYSTEMTIME，iOS 编不过）
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

#define HIK_STREAME_REALTIME 0
#define HIK_STREAME_FILE     1

// ---------------------------------------------------------------------------
// 每路回放的上下文
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
static NSMutableDictionary<NSNumber *, NSValue *> *gChanInfo = nil;   // uid -> {count, base}
static NSMutableDictionary<NSNumber *, id> *gVoiceBlocks = nil;       // voiceHandle -> block
static LONG gLiveSoundHandle = -1;

static void HikCtxInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gPlayCtxs = [NSMutableDictionary dictionary];
        gChanInfo = [NSMutableDictionary dictionary];
        gVoiceBlocks = [NSMutableDictionary dictionary];
    });
}

static HikPlayCtx *HikCtxFor(LONG handle) {
    if (!gPlayCtxs) return nil;
    HikPlayCtx *ctx = nil;
    @synchronized (gPlayCtxs) { ctx = gPlayCtxs[@(handle)]; }
    return ctx;
}

// 回放数据回调：SDK 内部线程回调，只做搬运，UI 操作回主线程
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
                NSLog(@"[HikMonSDK] PlayM4_GetPort failed err=%u", (unsigned)PlayM4_GetLastError(port));
                return;
            }
            PlayM4_SetStreamOpenMode(port, HIK_STREAME_REALTIME);
            if (!PlayM4_OpenStream(port, dwBufSize > 0 ? pBuffer : NULL, dwBufSize, 4 * 1024 * 1024)) {
                NSLog(@"[HikMonSDK] PlayM4_OpenStream failed err=%u", (unsigned)PlayM4_GetLastError(port));
                PlayM4_FreePort(port);
                return;
            }
            ctx.port = port;
            ctx.portReady = YES;
            PlayM4_SetDisplayBuf(port, 1);

            UIView *v = ctx.view;
            LONG p = port;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (v != nil && (v.window != nil || v.superview != nil)) {
                    if (!PlayM4_Play(p, (__bridge void *)v)) {
                        NSLog(@"[HikMonSDK] PlayM4_Play failed err=%u", (unsigned)PlayM4_GetLastError(p));
                    }
                }
                PlayM4_PlaySound(p);
            });
        } else if (dwDataType == NET_DVR_STREAMDATA || dwDataType == NET_DVR_AUDIOSTREAMDATA) {
            if (ctx.portReady && dwBufSize > 0) {
                PlayM4_InputData(ctx.port, pBuffer, dwBufSize);
            }
        }
    }
}

// 语音对讲回调
static void CALLBACK HikVoiceCB(LONG lVoiceComHandle, char *pRecvDataBuffer, DWORD dwBufSize,
                                BYTE byAudioFlag, void *pUser)
{
    @autoreleasepool {
        if (!gVoiceBlocks || dwBufSize == 0 || pRecvDataBuffer == NULL) return;
        id obj = nil;
        @synchronized (gVoiceBlocks) { obj = gVoiceBlocks[@(lVoiceComHandle)]; }
        void (^cb)(NSData *, int) = obj;
        if (!cb) return;
        NSData *data = [NSData dataWithBytes:pRecvDataBuffer length:dwBufSize];
        cb(data, (int)byAudioFlag);
    }
}

static void HikFillTime(NET_DVR_TIME *t, NSDate *date) {
    if (t == NULL) return;
    memset(t, 0, sizeof(NET_DVR_TIME));
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone localTimeZone];
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                         NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                 fromDate:date];
    t->dwYear = (DWORD)c.year;
    t->dwMonth = (DWORD)c.month;
    t->dwDay = (DWORD)c.day;
    t->dwHour = (DWORD)c.hour;
    t->dwMinute = (DWORD)c.minute;
    t->dwSecond = (DWORD)c.second;
}

@implementation HikMonSDK

// ---------------------------------------------------------------------------
// 全局
// ---------------------------------------------------------------------------
+ (BOOL)available { return YES; }

+ (NSString *)sdkVersion {
    DWORD v = NET_DVR_GetSDKBuildVersion();
    return [NSString stringWithFormat:@"%u.%u.%u.%u",
            (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
}

+ (void)globalInit {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NET_DVR_Init();
        NET_DVR_SetConnectTime(5000, 3);
        NET_DVR_SetReconnect(10000, TRUE);
        NET_DVR_SetRecvTimeOut(8000);
    });
}

+ (unsigned int)lastErrorCode { return (unsigned int)NET_DVR_GetLastError(); }

+ (NSString *)lastErrorText {
    DWORD e = NET_DVR_GetLastError();
    return [NSString stringWithFormat:@"err=%u", (unsigned)e];
}

+ (nullable NSString *)resolveHost:(NSString *)host {
    if (host.length == 0) return nil;
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *res = NULL;
    if (getaddrinfo(host.UTF8String, NULL, &hints, &res) != 0 || res == NULL) return nil;
    char buf[INET6_ADDRSTRLEN];
    NSString *out = nil;
    for (struct addrinfo *p = res; p != NULL; p = p->ai_next) {
        void *addr = (p->ai_family == AF_INET)
            ? (void *)&((struct sockaddr_in *)p->ai_addr)->sin_addr
            : (void *)&((struct sockaddr_in6 *)p->ai_addr)->sin6_addr;
        if (inet_ntop(p->ai_family, addr, buf, sizeof(buf)) != NULL) {
            out = [NSString stringWithUTF8String:buf];
            break;
        }
    }
    freeaddrinfo(res);
    return out;
}

+ (BOOL)setProtectKey:(NSString *)key {
    if (key.length == 0) return NO;
    NET_DVR_SDKLOCAL_CFG cfg;
    memset(&cfg, 0, sizeof(cfg));
    NSData *raw = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger n = MIN(raw.length, sizeof(cfg.byProtectKey));
    memcpy(cfg.byProtectKey, raw.bytes, n);
    BOOL ok = NET_DVR_SetSDKLocalConfig(&cfg);
    NSLog(@"[HikMonSDK] 码流加密设置 -> %d", (int)ok);
    return ok;
}

// ---------------------------------------------------------------------------
// 登录
// ---------------------------------------------------------------------------
+ (NSInteger)loginHost:(NSString *)host port:(int)port user:(NSString *)user password:(NSString *)pass {
    [self globalInit];
    HikCtxInit();

    NET_DVR_USER_LOGIN_INFO info;
    memset(&info, 0, sizeof(info));
    strncpy(info.sDeviceAddress, host.UTF8String ?: "", sizeof(info.sDeviceAddress) - 1);
    strncpy(info.sUserName, user.UTF8String ?: "", sizeof(info.sUserName) - 1);
    strncpy(info.sPassword, pass.UTF8String ?: "", sizeof(info.sPassword) - 1);
    info.wPort = (WORD)port;
    info.bUseAsynLogin = 0;

    NET_DVR_DEVICEINFO_V40 devInfo;
    memset(&devInfo, 0, sizeof(devInfo));

    LONG uid = NET_DVR_Login_V40(&info, &devInfo);
    if (uid < 0) {
        NSLog(@"[HikMonSDK] Login %@:%d failed err=%u", host, port, (unsigned)NET_DVR_GetLastError());
        return -1;
    }

    int nIP = devInfo.struDeviceV30.byIPChanNum + devInfo.struDeviceV30.byHighDChanNum * 256;
    int nA = devInfo.struDeviceV30.byChanNum;
    int startD = devInfo.struDeviceV30.byStartDChan;
    int startA = devInfo.struDeviceV30.byStartChan;
    int base = nIP > 0 ? (startD > 0 ? startD : 1) : (startA > 0 ? startA : 1);
    int cnt = nIP > 0 ? nIP : (nA > 0 ? nA : 8);

    int info2[2] = {cnt, base};
    @synchronized (gChanInfo) {
        gChanInfo[@(uid)] = [NSValue valueWithBytes:info2 objCType:@encode(int[2])];
    }
    NSLog(@"[HikMonSDK] 登录成功 %@:%d uid=%ld 通道=%d 基址=%d", host, port, (long)uid, cnt, base);
    return uid;
}

+ (void)logout:(NSInteger)userId {
    if (userId < 0) return;
    @synchronized (gChanInfo) { [gChanInfo removeObjectForKey:@(userId)]; }
    NET_DVR_Logout((LONG)userId);
}

+ (int)channelCount:(NSInteger)userId {
    if (!gChanInfo) return 1;
    NSValue *v = nil;
    @synchronized (gChanInfo) { v = gChanInfo[@(userId)]; }
    if (!v) return 1;
    int info2[2] = {1, 1};
    [v getValue:info2];
    return info2[0] > 0 ? info2[0] : 1;
}

+ (int)channelBase:(NSInteger)userId {
    if (!gChanInfo) return 1;
    NSValue *v = nil;
    @synchronized (gChanInfo) { v = gChanInfo[@(userId)]; }
    if (!v) return 1;
    int info2[2] = {1, 1};
    [v getValue:info2];
    return info2[1] > 0 ? info2[1] : 1;
}

// ---------------------------------------------------------------------------
// 实时预览
// ---------------------------------------------------------------------------
+ (NSInteger)startRealPlay:(NSInteger)userId channel:(int)channel subStream:(BOOL)subStream view:(UIView *)view {
    [self globalInit];
    if (userId < 0 || view == nil) return -1;

    NET_DVR_PREVIEWINFO pi;
    memset(&pi, 0, sizeof(pi));
    pi.lChannel        = (LONG)(channel > 0 ? channel : 1);
    pi.dwStreamType    = (DWORD)(subStream ? 1 : 0);
    pi.dwLinkMode      = 0;
    pi.hPlayWnd        = (__bridge void *)view;
    pi.bBlocked        = 0;
    pi.byProtoType     = 0;
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

+ (BOOL)makeKeyFrame:(NSInteger)userId channel:(int)channel {
    if (userId < 0) return NO;
    return NET_DVR_MakeKeyFrame((LONG)userId, (LONG)(channel > 0 ? channel : 1));
}

// ---------------------------------------------------------------------------
// 声音
// ---------------------------------------------------------------------------
+ (BOOL)openSound:(NSInteger)handle {
    if (handle < 0) return NO;
    BOOL ok = NET_DVR_OpenSound((LONG)handle);
    if (ok) gLiveSoundHandle = (LONG)handle;
    return ok;
}

+ (BOOL)closeSound {
    BOOL ok = NET_DVR_CloseSound();
    gLiveSoundHandle = -1;
    return ok;
}

+ (BOOL)setVolume:(NSInteger)handle volume:(int)volume {
    if (handle < 0) return NO;
    int v = volume < 0 ? 0 : (volume > 100 ? 100 : volume);
    return NET_DVR_Volume((LONG)handle, (WORD)v);
}

// ---------------------------------------------------------------------------
// 语音对讲
// ---------------------------------------------------------------------------
+ (NSInteger)startVoiceCom:(NSInteger)userId channel:(int)channel onData:(void (^)(NSData *, int))onData {
    if (userId < 0) return -1;
    HikCtxInit();

    LONG h = NET_DVR_StartVoiceCom_MR_V30((LONG)userId, (DWORD)(channel > 0 ? channel : 1),
                                          HikVoiceCB, NULL);
    if (h < 0) {
        NSLog(@"[HikMonSDK] StartVoiceCom_MR_V30 failed err=%u", (unsigned)NET_DVR_GetLastError());
        return -1;
    }
    if (onData) {
        @synchronized (gVoiceBlocks) { gVoiceBlocks[@(h)] = [onData copy]; }
    }
    NSLog(@"[HikMonSDK] 对讲句柄=%ld 通道=%d", (long)h, channel);
    return (NSInteger)h;
}

+ (BOOL)sendVoiceData:(NSInteger)handle data:(NSData *)data {
    if (handle < 0 || data.length == 0) return NO;
    return NET_DVR_VoiceComSendData((LONG)handle, (char *)data.bytes, (DWORD)data.length);
}

+ (void)stopVoiceCom:(NSInteger)handle {
    if (handle < 0) return;
    @synchronized (gVoiceBlocks) { [gVoiceBlocks removeObjectForKey:@(handle)]; }
    NET_DVR_StopVoiceCom((LONG)handle);
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
    para.dwSize = sizeof(para);
    para.struIDInfo.dwSize = sizeof(NET_DVR_STREAM_INFO);
    para.struIDInfo.dwChannel = (DWORD)(channel > 0 ? channel : 1);
    HikFillTime(&para.struBeginTime, from);
    HikFillTime(&para.struEndTime, to);
    para.hWnd = NULL;
    para.byDrawFrame = 0;
    para.byStreamType = 0;

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
    @synchronized (gPlayCtxs) { gPlayCtxs[@(h)] = ctx; }

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
        @synchronized (gPlayCtxs) { [gPlayCtxs removeObjectForKey:@(handle)]; }
        NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYSTOP, 0, NULL);
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
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYPAUSE, 0, NULL);
}

+ (BOOL)playbackResume:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYRESTART, 0, NULL);
}

+ (BOOL)playbackFast:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYFAST, 0, NULL);
}

+ (BOOL)playbackNormal:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYNORMAL, 0, NULL);
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

// ---------------------------------------------------------------------------
// ISAPI 透传
// ---------------------------------------------------------------------------
+ (NSString *)stdXML:(NSInteger)userId url:(NSString *)url body:(NSString *)body status:(NSString **)statusOut {
    if (userId < 0) return @"";
    NSData *urlData = [url dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bodyData = body.length ? [body dataUsingEncoding:NSUTF8StringEncoding] : nil;

    NET_DVR_XML_CONFIG_INPUT in;
    memset(&in, 0, sizeof(in));
    in.dwSize = sizeof(in);
    in.lpRequestUrl = (void *)urlData.bytes;
    in.dwRequestUrlLen = (DWORD)urlData.length;
    in.lpInBuffer = bodyData.length ? (void *)bodyData.bytes : NULL;
    in.dwInBufferSize = (DWORD)bodyData.length;
    in.dwRecvTimeOut = 8000;

    NSMutableData *outData = [NSMutableData dataWithLength:256 * 1024];
    NSMutableData *stData = [NSMutableData dataWithLength:8 * 1024];

    NET_DVR_XML_CONFIG_OUTPUT out;
    memset(&out, 0, sizeof(out));
    out.dwSize = sizeof(out);
    out.lpOutBuffer = outData.mutableBytes;
    out.dwOutBufferSize = (DWORD)outData.length;
    out.lpStatusBuffer = stData.mutableBytes;
    out.dwStatusSize = (DWORD)stData.length;

    BOOL ok = NET_DVR_STDXMLConfig((LONG)userId, &in, &out);
    if (!ok) {
        NSLog(@"[HikMonSDK] STDXML %@ failed err=%u", url, (unsigned)NET_DVR_GetLastError());
        return @"";
    }
    DWORD n = out.dwReturnedXMLSize;
    if (n == 0 || n > outData.length) return @"";
    if (statusOut) {
        NSString *st = [[NSString alloc] initWithBytes:stData.bytes
                                                length:MIN(strlen((const char *)stData.bytes), stData.length)
                                              encoding:NSUTF8StringEncoding];
        *statusOut = st ?: @"";
    }
    return [[NSString alloc] initWithBytes:outData.bytes length:n encoding:NSUTF8StringEncoding] ?: @"";
}

@end

#else   // HAS_HIKSDK == 0 —— 空实现

@implementation HikMonSDK
+ (BOOL)available { return NO; }
+ (NSString *)sdkVersion { return @"未集成"; }
+ (void)globalInit {}
+ (unsigned int)lastErrorCode { return 0; }
+ (NSString *)lastErrorText { return @"未集成 HCNetSDK"; }
+ (NSString *)resolveHost:(NSString *)host { return host; }
+ (BOOL)setProtectKey:(NSString *)key { return NO; }
+ (NSInteger)loginHost:(NSString *)h port:(int)p user:(NSString *)u password:(NSString *)pw { return -1; }
+ (void)logout:(NSInteger)userId {}
+ (int)channelCount:(NSInteger)userId { return 1; }
+ (int)channelBase:(NSInteger)userId { return 1; }
+ (NSInteger)startRealPlay:(NSInteger)u channel:(int)c subStream:(BOOL)s view:(UIView *)v { return -1; }
+ (void)stopRealPlay:(NSInteger)handle {}
+ (BOOL)makeKeyFrame:(NSInteger)u channel:(int)c { return NO; }
+ (BOOL)openSound:(NSInteger)handle { return NO; }
+ (BOOL)closeSound { return NO; }
+ (BOOL)setVolume:(NSInteger)h volume:(int)v { return NO; }
+ (NSInteger)startVoiceCom:(NSInteger)u channel:(int)c onData:(void (^)(NSData *, int))cb { return -1; }
+ (BOOL)sendVoiceData:(NSInteger)h data:(NSData *)d { return NO; }
+ (void)stopVoiceCom:(NSInteger)handle {}
+ (NSInteger)startPlayback:(NSInteger)u channel:(int)c from:(NSDate *)f to:(NSDate *)t view:(UIView *)v { return -1; }
+ (void)stopPlayback:(NSInteger)handle {}
+ (BOOL)playbackPause:(NSInteger)handle { return NO; }
+ (BOOL)playbackResume:(NSInteger)handle { return NO; }
+ (BOOL)playbackFast:(NSInteger)handle { return NO; }
+ (BOOL)playbackNormal:(NSInteger)handle { return NO; }
+ (int)playbackPositionMillisecond:(NSInteger)handle { return 0; }
+ (int)playbackTotalMillisecond:(NSInteger)handle { return 0; }
+ (NSString *)stdXML:(NSInteger)u url:(NSString *)url body:(NSString *)b status:(NSString **)s { return @""; }
@end

#endif
