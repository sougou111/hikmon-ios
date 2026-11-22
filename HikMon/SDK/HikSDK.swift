import Foundation
import UIKit

/// 统一的后端抽象：SDK 可用时走 SDK（8000 私有协议），否则回落到 ISAPI+RTSP
enum Backend {
    case sdk
    case rtsp
}

final class HikSession {
    let device: Device
    private(set) var userId: Int = -1
    private(set) var realPlayHandle: Int = -1
    private(set) var playbackHandle: Int = -1

    init(device: Device) {
        self.device = device
    }

    static var sdkReady: Bool { HCNetSDKBridge.sdkAvailable() }
    static var sdkVersion: String { HCNetSDKBridge.sdkVersion() }

    /// 走 SDK 登录（端口用 device.sdkPort，默认 8000）
    @discardableResult
    func loginSDK() -> Bool {
        guard HikSession.sdkReady else { return false }
        HCNetSDKBridge.globalInit()
        let uid = HCNetSDKBridge.loginHost(device.host, port: Int32(device.sdkPort),
                                           user: device.user, password: device.pass)
        userId = uid
        return uid >= 0
    }

    func logout() {
        stopRealPlay()
        stopPlayback()
        if userId >= 0 { HCNetSDKBridge.logout(userId) }
        userId = -1
    }

    // MARK: 实时

    func startRealPlay(channel: Int, sub: Bool, in view: UIView) -> Bool {
        guard userId >= 0 else { return false }
        stopRealPlay()
        let h = HCNetSDKBridge.startRealPlay(userId, channel: Int32(channel),
                                             streamType: sub ? 1 : 0, view: view)
        realPlayHandle = h
        return h >= 0
    }

    func stopRealPlay() {
        if realPlayHandle >= 0 { HCNetSDKBridge.stopRealPlay(realPlayHandle) }
        realPlayHandle = -1
    }

    func openSound() -> Bool { HCNetSDKBridge.openSound(realPlayHandle) }
    func closeSound() -> Bool { HCNetSDKBridge.closeSound(realPlayHandle) }

    func startTalk() -> Bool { HCNetSDKBridge.startTalk(userId) }
    func stopTalk() { HCNetSDKBridge.stopTalk() }

    func ptz(cmd: Int, stop: Bool) -> Bool {
        HCNetSDKBridge.ptz(userId, channel: Int32(ptzChannel), cmd: Int32(cmd), stop: stop)
    }
    var ptzChannel: Int = 1

    // MARK: 回放

    func startPlayback(channel: Int, from: Date, to: Date, in view: UIView) -> Bool {
        guard userId >= 0 else { return false }
        stopPlayback()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let h = HCNetSDKBridge.startPlayback(userId, channel: Int32(channel),
                                             startTime: f.string(from: from),
                                             endTime: f.string(from: to),
                                             view: view)
        playbackHandle = h
        return h >= 0
    }

    func stopPlayback() {
        if playbackHandle >= 0 { HCNetSDKBridge.stopPlayback(playbackHandle) }
        playbackHandle = -1
    }

    func pause() { HCNetSDKBridge.playbackPause(playbackHandle) }
    func resume() { HCNetSDKBridge.playbackResume(playbackHandle) }
    func seek(_ seconds: Int) { HCNetSDKBridge.playbackSeek(playbackHandle, seconds: Int32(seconds)) }
}

/// SDK 的画面容器：真实 UIView，直接交给 SDK 渲染
struct SDKVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        v.contentMode = .scaleAspectFit
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
