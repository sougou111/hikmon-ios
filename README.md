# 瑞丰监控 iOS（HikMon）

跟安卓 `瑞丰监控 8.1` **同一套界面和逻辑**，取流全部走官方海康 HCNetSDK（8000 私有协议），
不用 RTSP / VLCKit / ISAPI 取流（ISAPI 只在「设备诊断」里做只读查询）。

## 与安卓版一致的页面结构

顶栏固定：左胶囊（设备管理 / 返回首页 / 返回设备 / 返回）+ 中间「监控」标题与副标题 + 右侧「⏸ 暂停 / ▶ 播放」；
底部固定三行运行日志，点一下进日志页。配色、圆角、间距照抄安卓（BG `#0E1116`、卡片 `#171B22`、
描边 `#262C36`、主色 `#3D8BFF`、收藏星 `#FFC53D`、对讲绿 `#34C759`）。

| 页面 | 内容 |
|---|---|
| 首页 | 每台设备一张卡：名称 + `IP:端口 · 收藏 N 路 · 语音通道 X` + 「通道管理」；卡内 2×2 显示收藏的 4 路，右上角 ⛶ 进单通道，点画面进单通道，长按进回放 |
| 服务器管理 | 「＋ 添加服务器」表单（名称/主机地址/端口/用户名/密码/验证码）+ 已保存列表（通道管理、设置） |
| 通道管理 | 每页 6 路（3×2），左右滑动翻页；每路底部「通道 N」+ ☆/★ 收藏 + 🎤 语音通道；点画面看回放，长按就地预览 |
| 单通道 | SDK 直渲染 + 双指缩放 1–4×、单指拖动、双击复位；「🔊 静音 / 🔇 取消静音」+「回放」+ 大按钮「按住说话」 |
| 回放 | 画面 → 时间（`MM-dd HH:mm:ss`）+ 状态 → 竖向时间轴（拖动选时间、双指缩放视野 10–360 分钟、点按跳转）→ 快捷 -1时/-10分/+10分/+1时 → 「播放/暂停」「2× 倍速」「现在」 |
| 设置 | 连接参数（名称/地址/SDK 端口/用户名/密码，点一行弹输入框）、画面（主/子码流）、网络（地址解析 4 档）、音频（模式/编码/通道）、诊断入口、删除服务器 |
| 设备诊断 | `NET_DVR_STDXMLConfig` 只读拉 deviceInfo / 移动侦测 / 智能规则 / 取流参数 / 音频通道，可复制结果 |
| 日志 | 运行日志全文，可复制、可清空；底部三行是同一份缓冲的尾巴 |

## 功能对照

- 收藏：⭐ 决定首页 2×2 显示哪 4 路；没收藏的位置显示「未收藏 / 通道」
- 语音通道：🎤 标记对讲用哪一路；单通道「按住说话」走 `NET_DVR_StartVoiceCom_MR_V30` + `NET_DVR_VoiceComSendData`（G.711 µ-law / A-law 可切）
- 声音：单通道默认开声，静音走 `NET_DVR_CloseSound()`；对讲时设备回传的 G.711 在本机解码播放（监听）
- 回放：`NET_DVR_PlayBackByTime_V40` → 数据回调 → PlayM4 解码到 UIView；暂停/继续/2×/跳转都走 `NET_DVR_PlayBackControl`
- 码流：设备级「主码流 / 子码流」，映射 `dwStreamType 0/1`
- 地址解析：IPv4 优先 / 仅 IPv4 / 仅 IPv6 / IPv6 优先（getaddrinfo 逐个候选尝试登录）
- 验证码：`NET_DVR_SetSDKLocalConfig.byProtectKey`，登录前设置

## 出包

`project.yml`（XcodeGen，无 CocoaPods）→ GitHub Actions `macos-15` 上
`xcodegen generate` + `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO` → 打 `HikMon-unsigned.ipa`。

本机没有 git，推送走 GitHub Git Data API：`..\hikmon_push2.ps1`；等 CI + 拉产物：`..\hikmon_build.ps1`。

## 版本

- 1.03：通道管理补上左右滑动翻页（并加 ‹ › 箭头兜底）；底部日志条去掉，改到「设备管理 → 日志记录」；服务器配置落 Documents + 旧数据迁移 + 备份/恢复
- 1.02：去掉设置里的音频模式/编码/通道（全走 SDK 默认）
- 1.01：按安卓 1:1 重写界面（8 页、收藏、语音通道、按安卓节奏的回放时间轴），对讲改 MR_V30 + G.711
- 1.00：首版原生 HCNetSDK 取流

## 数据不会因为覆盖安装丢

- 服务器列表存在 App 的 `Documents/hikmon-devices.json`（覆盖安装/升级不动这个目录），同时镜像一份到 UserDefaults
- 启动时会自动迁移老版本用过的 key（`hikmon.devices` / `hikmon.devices.v2` / `v3`）和旧字段结构
- 「设备管理 → 备份配置」导出 JSON 到「文件」App（可发微信/存 iCloud）；换机或删了重装用「恢复配置」导入
- Info.plist 开了 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`，「文件 → 我的 iPhone → 瑞丰监控」里能直接看到备份

## 已知边界

- 需要设备开 8000 端口（SDK 私有协议）
- H.265 / 加密码流 / P2P 依赖设备固件与 SDK 版本
- 未签名 IPA，用 Sideloadly / 全能签 / TrollStore 自签安装；首次启动要允许「本地网络」和「麦克风」
