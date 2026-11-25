# HikMon for iOS — 海康 NVR / 摄像机监控客户端

用**官方海康设备网络 SDK（HCNetSDK V6.1.11.5 iOS）** 直连设备，走 8000 私有协议取流，
画面由 SDK 自己渲染到 `UIView`（`NET_DVR_RealPlay_V40`），回放走
`NET_DVR_PlayBackByTime_V40` + 数据回调 + PlayM4 解码。**不再用 RTSP / VLCKit / ISAPI。**

## 功能

| 模块 | 实现 |
|---|---|
| 设备管理 | 列表 + 新增/编辑合并成一个设置页：名称、地址（IP/域名）、SDK 端口、用户名、密码、主/子码流、地址解析模式、通道数；左滑删除；「测试登录」直接打一次 `NET_DVR_Login_V40` 并读回通道数 |
| 网格预览 | SDK 直渲染 `NET_DVR_RealPlay_V40` + `hPlayWnd = UIView`，2×2 一页，16 通道分页；每格右上角 ⛶ 进单通道 |
| 单通道 | SDK 直渲染 + 双指缩放 1–4×、单指拖动、双击复位 + 「声音」按钮（`NET_DVR_OpenSound` / `NET_DVR_CloseSound()`）+ 「按住说话」（`NET_DVR_StartVoiceCom_V30` / `NET_DVR_StopVoiceCom(handle)`） |
| 回放 | `NET_DVR_PlayBackByTime_V40` → `NET_DVR_SetPlayDataCallBack` → `NET_DVR_PlayBackControl(PLAYSTART)` → PlayM4 解码到 `UIView`；播放/暂停/进度拖动 |
| 会话复用 | 同一设备（host+port+user+pass）只登录一次，所有通道共用 `userId`；登录或开流失败自动清会话重登一次 |
| 诊断日志 | 启动即把 stderr（含 HCNetSDK / PlayM4 的 NSLog）接管进环形缓冲，右上角放大镜按钮实时看、一键分享；回放位置连续 2 秒不动会自动记一条「回放停滞」 |

## 目录

```
HikMon/
  App/HikMonApp.swift              入口
  Model/Device.swift               设备模型 + UserDefaults 存储
  SDK/HikMonSDK.h/.mm              ObjC++ 门面：所有 HCNetSDK / PlayM4 调用都在这里
  SDK/HikSDK.swift                 HikSession 会话池（一键登录/复用/重登）
  SDK/inc/                         SDK 头文件（HCNetSDK.h 已转 UTF-8）
  SDK/lib/sdk.part1…6              官方 Release-iphoneos 13 个 .a 的 zip 分片，CI 里 cat 回来
  Player/HikPlayers.swift          LivePlayer / LiveGrid / PlaybackEngine
  Views/SDKCanvas.swift            SDK 渲染画布 + 缩放拖动 + SwiftUI 包装
  Views/LiveView.swift             2×2 网格
  Views/SingleChannelView.swift    单通道全屏
  Views/PlaybackView.swift         回放
  Views/RootView.swift             设备列表
  Views/DeviceEditView.swift       设备设置页
```

## 出包（Windows 上也能做）

工程只有 `project.yml`（XcodeGen），**没有 CocoaPods**。

- CI：push 到 `main` 触发 `.github/workflows/build-ipa.yml`（macos-15 runner）
  1. `cat HikMon/SDK/lib/sdk.part* > /tmp/sdk.zip` → 解压出 13 个 `.a`
  2. `xcodegen generate`
  3. `xcodebuild -project HikMon.xcodeproj -sdk iphoneos CODE_SIGNING_ALLOWED=NO`
  4. 打成 `Payload/HikMon.app` → `HikMon-unsigned.ipa`，artifact 名 `HikMon-unsigned-ipa`
- 本机：`xcodegen generate && open HikMon.xcodeproj`（需 macOS + Xcode 15/16）

## 安装

未签名 IPA 用 **全能签 / Sideloadly / AltStore / TrollStore** 自签安装；装上后首次运行
会申请「本地网络」权限（连 LAN 里的 NVR 必须允许），对讲还会申请麦克风。

## 已知边界

- 需要设备开放 8000 端口（SDK 私有协议）；只开 80/554 的老设备用不了
- H.265、加密码流、P2P 穿透依赖设备与 SDK 版本，老固件可能只出 H.264
- 网格每页 4 路，最多翻 4 页（16 通道）；再多请改 `LiveGrid.channels` 上限
- 云台接口（`NET_DVR_PTZControl_Other`）已在桥接层留好，UI 暂未接
