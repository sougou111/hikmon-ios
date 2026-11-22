# 接入海康 HCNetSDK（可选）

> 结论先说：**SDK 不能从 iVMS 4500+ 里抽出来复用**——那是静态链接进 `HikDemo` 主二进制的（127 个包里没有独立 framework，只有 365 处 `NET_DVR_*` 符号和 `Pack_SDK_HCNetSDK_IOS` 编译路径）。静态代码无法重新链接到别的 App。
>
> 正确做法是从海康官方拿 SDK，本工程已经把接入层写好了，放进去即可。

## 一、拿 SDK（官方、免费）

1. 打开 <https://open.hikvision.com> → 注册/登录（个人开发者即可）。
2. 「开发 → SDK 下载 → 设备网络SDK（iOS）」。
3. 同意协议，下载（约 200–300 MB，含 `HCNetSDK.framework` / `libhcnetsdk.a` + 头文件 + `PlayM4` 播放库）。
4. 解压后确认里面至少有：
   - `inc/HCNetSDK.h`、`inc/PlayM4.h`、`inc/HCNetSDKCom/…`
   - `lib/libhcnetsdk.a` 或 `HCNetSDK.framework`

## 二、放进工程

```
HikMon-iOS/
  HikMon/
    SDK/
      HCNetSDKBridge.h        ← 已写好的桥接（不用改）
      HCNetSDKBridge.m        ← 已写好的桥接（不用改）
      HikMon-Bridging-Header.h
      HikSDK.swift
      inc/                    ← 把 SDK 的 inc/ 整个拷进来
      lib/                    ← 把 libhcnetsdk.a（或 HCNetSDK.framework）拷进来
```

## 三、打开开关

`project.yml` 里改两处：

```yaml
        GCC_PREPROCESSOR_DEFINITIONS:
          - "$(inherited)"
          - "HAS_HIKSDK=1"          # ← 0 改成 1

        # 取消注释：
        HEADER_SEARCH_PATHS:
          - "$(inherited)"
          - "$(SRCROOT)/HikMon/SDK/inc"
        LIBRARY_SEARCH_PATHS:
          - "$(inherited)"
          - "$(SRCROOT)/HikMon/SDK/lib"
        OTHER_LDFLAGS:
          - "$(inherited)"
          - "-lhcnetsdk"
          - "-lPlayCtrl"            # 播放库（SDK 包里带）
          - "-lstdc++"
```

> 用 `HCNetSDK.framework` 的话，改成 `FRAMEWORK_SEARCH_PATHS` + `-framework HCNetSDK`。

然后 `xcodegen generate && pod install`，重新出包。

## 四、已经接好的能力

| 能力 | SDK 调用 | 说明 |
|---|---|---|
| 登录（8000） | `NET_DVR_Login_V40` | 你只要填 SDK 端口（默认 8000，你的 44691 就是映射到它） |
| 实时预览 | `NET_DVR_RealPlay_V40` | `dwStreamType` 0=主码流 / 1=子码流 |
| 回放 | `NET_DVR_PlayBackByTime_V40` + `NET_DVR_PLAYSTART` | 按起止时间，支持暂停/恢复/定位 |
| 声音 | `NET_DVR_OpenSound` / `CloseSound` | 预览和回放都能出声 |
| 对讲 | `NET_DVR_StartVoiceCom_V30` / `StopVoiceCom` | SDK 自己采麦克风，不用写音频管线 |
| 云台 | `NET_DVR_PTZControl_Other` | 1上 2下 3左 4右 11放大 12缩小，松手传 stop=1 |
| 断线重连 | `NET_DVR_SetReconnect` | 已在 `globalInit` 里开 |

## 五、和 RTSP 的关系

两套并存：

- SDK 可用（`HikSession.sdkReady == true`）→ 优先 SDK：**只需要一个端口**，回放/对讲/声音全有。
- SDK 不可用 → 自动回落 ISAPI + RTSP：需要 80/554 两个端口。

这样你自签装机后，把 SDK 放进仓库跑一次 CI，出来的 IPA 就等价于 iVMS 4500+ 的取流能力（除了它的云中转和企业功能——那些你不要）。
