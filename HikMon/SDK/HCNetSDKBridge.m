//
//  HCNetSDKBridge.m
//  只有 HAS_HIKSDK=1 时才真正编译 SDK 调用；=0 时整个文件是空的，构建照常通过。
//

#import "HCNetSDKBridge.h"

#if HAS_HIKSDK

#import "HCNetSDK.h"

static NSInteger gUserId = -1;

static NSString *Err(void) {
    DWORD code = NET_DVR_GetLastError();
    return [NSString stringWithFormat:@"HCNetSDK 错误码 %u", (unsigned)code];
}

static void FillTime(NET_DVR_TIME *t, NSString *s) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *d = [f dateFromString:s] ?: [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                           NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:d];
    t->dwYear = (DWORD)c.year;
    t->dwMonth = (DWORD)c.month;
    t->dwDay = (DWORD)c.day;
    t->dwHour = (DWORD)c.hour;
    t->dwMinute = (DWORD)c.minute;
    t->dwSecond = (DWORD)c.second;
}

@implementation HCNetSDKBridge

+ (BOOL)sdkAvailable { return YES; }

+ (NSString *)sdkVersion {
    return [NSString stringWithUTF8String:NET_DVR_GetSDKBuildVersion()];
}

+ (void)globalInit {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NET_DVR_Init();
        NET_DVR_SetConnectTime(3000, 1);
        NET_DVR_SetReconnect(5000, YES);
        NET_DVR_SetLogToFile(3, [NSTemporaryDirectory() stringByAppendingPathComponent:@"hiklog"], YES);
    });
}

+ (NSInteger)loginHost:(NSString *)host port:(int)port user:(NSString *)user password:(NSString *)pass {
    [self globalInit];

    NET_DVR_USER_LOGIN_INFO info = {0};
    strncpy(info.sDeviceAddress, host.UTF8String, sizeof(info.sDeviceAddress) - 1);
    info.wPort = (WORD)port;
    strncpy(info.sUserName, user.UTF8String, sizeof(info.sUserName) - 1);
    strncpy(info.sPassword, pass.UTF8String, sizeof(info.sPassword) - 1);
    info.bUseAsynLogin = 0;

    NET_DVR_DEVICEINFO_V40 dev = {0};
    LONG uid = NET_DVR_Login_V40(&info, &dev);
    if (uid < 0) return -1;
    gUserId = uid;
    return uid;
}

+ (void)logout:(NSInteger)userId {
    if (userId >= 0) NET_DVR_Logout((LONG)userId);
}

+ (NSInteger)startRealPlay:(NSInteger)userId channel:(int)channel streamType:(int)streamType view:(UIView *)view {
    NET_DVR_PREVIEWINFO pi = {0};
    pi.lChannel = channel;
    pi.dwStreamType = (DWORD)streamType;   // 0 主码流 / 1 子码流
    pi.dwLinkMode = 0;                     // 0 = TCP
    pi.bBlocked = 1;
    pi.hPlayWnd = (void *)CFBridgingRetain(view);

    LONG h = NET_DVR_RealPlay_V40((LONG)userId, &pi, NULL, NULL);
    return h < 0 ? -1 : h;
}

+ (void)stopRealPlay:(NSInteger)handle {
    if (handle >= 0) NET_DVR_StopRealPlay((LONG)handle);
}

+ (NSInteger)startPlayback:(NSInteger)userId channel:(int)channel startTime:(NSString *)start endTime:(NSString *)end view:(UIView *)view {
    NET_DVR_VOD_PARA para = {0};
    para.struIDInfo.dwSize = sizeof(NET_DVR_STREAM_INFO);
    para.struIDInfo.dwChannel = (DWORD)channel;
    FillTime(&para.struBeginTime, start);
    FillTime(&para.struEndTime, end);
    para.hWnd = (void *)CFBridgingRetain(view);

    LONG h = NET_DVR_PlayBackByTime_V40((LONG)userId, &para);
    if (h < 0) return -1;
    NET_DVR_PlayBackControl((LONG)h, NET_DVR_PLAYSTART, 0, NULL);
    return h;
}

+ (void)stopPlayback:(NSInteger)handle {
    if (handle >= 0) {
        NET_DVR_StopPlayBack((LONG)handle);
    }
}

+ (void)playbackPause:(NSInteger)handle {
    if (handle >= 0) NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYPAUSE, 0, NULL);
}

+ (void)playbackResume:(NSInteger)handle {
    if (handle >= 0) NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYRESTART, 0, NULL);
}

+ (void)playbackSeek:(NSInteger)handle seconds:(int)seconds {
    if (handle < 0) return;
    int pos = seconds * 1000;
    NET_DVR_PlayBackControl((LONG)handle, NET_DVR_PLAYSETPOS, pos, NULL);
}

+ (BOOL)openSound:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_OpenSound((LONG)handle);
}

+ (BOOL)closeSound:(NSInteger)handle {
    if (handle < 0) return NO;
    return NET_DVR_CloseSound((LONG)handle);
}

+ (BOOL)startTalk:(NSInteger)userId {
    if (userId < 0) return NO;
    return NET_DVR_StartVoiceCom_V30((LONG)userId, 1, NULL, NULL);
}

+ (void)stopTalk {
    NET_DVR_StopVoiceCom(0);
}

+ (BOOL)ptz:(NSInteger)userId channel:(int)channel cmd:(int)cmd stop:(BOOL)stop {
    if (userId < 0) return NO;
    return NET_DVR_PTZControl_Other((LONG)userId, channel, cmd, stop ? 1 : 0);
}

+ (NSString *)lastError { return Err(); }

@end

#else

@implementation HCNetSDKBridge
+ (BOOL)sdkAvailable { return NO; }
+ (NSString *)sdkVersion { return @"未集成"; }
+ (void)globalInit {}
+ (NSInteger)loginHost:(NSString *)h port:(int)p user:(NSString *)u password:(NSString *)pw { return -1; }
+ (void)logout:(NSInteger)i {}
+ (NSInteger)startRealPlay:(NSInteger)i channel:(int)c streamType:(int)s view:(UIView *)v { return -1; }
+ (void)stopRealPlay:(NSInteger)h {}
+ (NSInteger)startPlayback:(NSInteger)i channel:(int)c startTime:(NSString *)a endTime:(NSString *)b view:(UIView *)v { return -1; }
+ (void)stopPlayback:(NSInteger)h {}
+ (void)playbackPause:(NSInteger)h {}
+ (void)playbackResume:(NSInteger)h {}
+ (void)playbackSeek:(NSInteger)h seconds:(int)s {}
+ (BOOL)openSound:(NSInteger)h { return NO; }
+ (BOOL)closeSound:(NSInteger)h { return NO; }
+ (BOOL)startTalk:(NSInteger)i { return NO; }
+ (void)stopTalk {}
+ (BOOL)ptz:(NSInteger)i channel:(int)c cmd:(int)m stop:(BOOL)s { return NO; }
+ (NSString *)lastError { return @"SDK 未集成"; }
@end

#endif
