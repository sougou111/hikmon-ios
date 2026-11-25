# 海康 HCNetSDK（iOS）接入笔记

SDK 来源：官方 `HCNetSDKV6.1.11.5_build20151204_iOS_ZH`。
`lib/Release-iphoneos` 里 13 个静态库共 204MB（每个都是 armv7+arm64 的 fat archive），
GitHub 单文件上限 100MB，所以仓库里存的是拆成 6 份（每份 ~13.8MB）的 zip 分片，
CI 里 `cat sdk.part* > sdk.zip && unzip` 还原。

## 一、必须踩的坑（都已在代码里绕过）

1. **`HCNetSDK.h` 只能在 Objective-C++ 里 include。**
   它在 `__APPLE__` 分支把 `NET_DVR_API` 定义成 `extern "C"`，纯 C/ObjC 编译直接语法错误。
   → 所以桥接实现是 `HikMonSDK.mm`。

2. **它还会 `#define BOOL int` / `#define NULL 0` / `#define TRUE 1`。**
   所以：
   - 必须先 `#import <Foundation/Foundation.h>`、`<UIKit/UIKit.h>`，再 include 它；
   - 绝不能让它进 Swift 的 bridging header（会毁掉整份 Foundation）。
   bridging header 里只有 `HikMonSDK.h`（纯 ObjC，无 SDK 类型）。

3. **`plaympeg4.h` 引用了 Windows 的 `SYSTEMTIME`，iOS 编不过。**
   → 不用它，在 `.mm` 里手写用到的十几个 PlayM4 声明（`extern "C"`，符号名与库里一致）。

4. **`NET_DVR_CloseSound()` 没有参数**（不是传 handle）；**`NET_DVR_StopVoiceCom(lHandle)` 要传句柄。**
   `NET_DVR_GetSDKBuildVersion()` 返回 `DWORD`（0x06010B05 → 6.1.11.5），不是字符串。

5. **`-lstdc++` 在 Xcode 10+ 不存在**，这些库其实是 C++ 写的，链接 `-lc++` 就够。

6. **`AIP.a` 没有 `lib` 前缀**，`-lAIP` 找不到；CI 里补了一份 `libAIP.a`。

7. **头文件是 GBK 编码**（610KB 非 ASCII 字节）。CLANG 按 UTF-8 解析注释会告警，
   GBK 尾字节还有可能是 `0x5C`（`\`）导致注释吞行。→ 已整体转成 UTF-8 再入库。

8. 静态库需要的系统框架（从 demo 工程 + 符号扫描得出）：
   `AVFoundation/AVFAudio/AudioToolbox/VideoToolbox/CoreMedia/CoreVideo/CoreGraphics/
   QuartzCore/OpenGLES/GLKit/CFNetwork/SystemConfiguration/Security` + `-lz -liconv -lbz2 -lc++`。

9. **GitHub Blobs API 单个请求体超过 ~32MB 会返回 401 Bad credentials**（大 payload 触发，
   和 token 无关）。实测 30.2MB 请求体 OK、40MB 401。→ 每个分片控制在 14MB 以保证 base64 后 <20MB。

## 二、关键调用（照这个写）

```c
// 登录
NET_DVR_USER_LOGIN_INFO info = {0};
strncpy(info.sDeviceAddress, host, sizeof(info.sDeviceAddress)-1);
info.wPort = 8000; info.byLoginMode = 0; info.bUseAsynLogin = 0;
NET_DVR_DEVICEINFO_V40 dev = {0};
LONG uid = NET_DVR_Login_V40(&info, &dev);
int chans = dev.struDeviceV30.byChanNum + dev.struDeviceV30.byIPChanNum
          + dev.struDeviceV30.byHighDChanNum * 256;

// 实时预览（SDK 内部解码，直接画到 UIView；bBlocked=0 才不阻塞 UI）
NET_DVR_PREVIEWINFO pi = {0};
pi.lChannel = ch; pi.dwStreamType = sub ? 1 : 0; pi.dwLinkMode = 0;
pi.hPlayWnd = (__bridge void *)view; pi.bBlocked = 0; pi.byProtoType = 0;
LONG h = NET_DVR_RealPlay_V40(uid, &pi, NULL, NULL);

// 声音
NET_DVR_OpenSound(h); NET_DVR_Volume(h, 80); NET_DVR_CloseSound();   // 无参！

// 对讲
LONG v = NET_DVR_StartVoiceCom_V30(uid, 1, 0, NULL, NULL);
NET_DVR_StopVoiceCom(v);                                            // 传句柄！

// 回放（外部解码）
NET_DVR_VOD_PARA para = {0};
para.dwSize = sizeof(para);
para.struIDInfo.dwSize = sizeof(NET_DVR_STREAM_INFO);
para.struIDInfo.dwChannel = ch;
para.struBeginTime = ...; para.struEndTime = ...;
para.hWnd = NULL;                       // 走数据回调
LONG p = NET_DVR_PlayBackByTime_V40(uid, &para);
NET_DVR_SetPlayDataCallBack(p, cb, (DWORD)p);
NET_DVR_PlayBackControl(p, NET_DVR_PLAYSTART, 0, NULL);
// 回调：NET_DVR_SYSHEAD -> PlayM4_GetPort / SetStreamOpenMode(0) / OpenStream / Play(view) / PlaySound
//       NET_DVR_STREAMDATA|NET_DVR_AUDIOSTREAMDATA -> PlayM4_InputData
// 进度：NET_DVR_PlayBackControl(p, NET_DVR_PLAYGETTIME, 0, &ms)   定位：PLAYSETPOS
```

## 三、错误码对照（`NET_DVR_GetLastError`）

`1` 用户名密码错 · `2` 权限不足 · `4` 通道号错 · `7` 连不上设备（IP/端口/防火墙）·
`10` 解码失败 · `12` 设备不在线 · `29` 设备命令执行失败 · `43` 设备不支持 · `96` 网络断开
（`HikMonSDK.mm` 里 `HikErrText()` 就是这张表）
