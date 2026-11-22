# HikMon for iOS — 海康 NVR / 摄像机监控客户端

只走 **海康 ISAPI + 标准 RTSP**，不打包任何厂商 SDK（没有 PlayM4、没有 DahuaEngine），所以授权干净、可上架。

## 功能

- 设备管理：IP / ISAPI 端口(80) / RTSP 端口(554) / 账号密码，多设备保存
- 通道发现：`/ISAPI/ContentMgmt/InputProxy/channels`（NVR）与 `/ISAPI/Streaming/channels`（IPC）双路兜底
- 实时预览：RTSP `rtsp://user:pass@host:554/Streaming/Channels/101`（主码流）/ `102`（子码流），2 列宫格
- 全屏播放 + 云台（`/ISAPI/PTZCtrl/channels/<ch>/continuous`）
- 抓图：`/ISAPI/Streaming/channels/<id>/picture` → 存相册
- 回放：`rtsp://user:pass@host:554/Streaming/tracks/<ch>01?starttime=20260101T000000Z&endtime=...`
- 子码流开关（多画面省流量）

## 目录

```
HikMon/
  App/HikMonApp.swift          入口
  Model/Device.swift           设备/通道模型 + UserDefaults 存储
  Net/ISAPI.swift              ISAPI 客户端（HTTP Digest 交给 URLSession）
  Player/PlayerBox.swift       VLCKit 封装（RTSP 拉流 + 硬解）
  Views/RootView.swift         设备列表
  Views/DeviceEditView.swift   添加/编辑 + 拉取通道
  Views/LiveView.swift         宫格预览 / 全屏 / 云台 / 抓图
  Views/PlaybackView.swift     回放
  Resources/Info.plist         局域网权限、相册、ATS
```

## 出包

- GitHub Actions：push 到 main 自动跑 `.github/workflows/build-ipa.yml`，产物 `HikMon-unsigned-ipa`
- 本地：`xcodegen generate && pod install && open HikMon.xcworkspace`（需要 macOS + Xcode 15）

未签名 IPA 用 Sideloadly / AltStore 自签安装。

## 已知边界

- RTSP 走 TCP（`:rtsp-tcp`），弱网更稳，延迟略高
- H.265 需要设备开启且 VLCKit 支持；老固件只能 H.264
- 没有 P2P 穿透：远程访问需要公网映射 / DDNS / VPN
- 双向对讲、报警订阅、智能检索暂未实现（ISAPI 端点已留注释）
