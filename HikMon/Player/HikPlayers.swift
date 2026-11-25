import Foundation
import UIKit
import AVFoundation
import Combine

// MARK: - 单通道实时播放器

final class LivePlayer: ObservableObject, Identifiable {
    let device: Device
    let channel: Int
    let canvas = SDKCanvasView()

    @Published private(set) var status: String = "未开始"
    @Published private(set) var failed = false
    @Published private(set) var soundOn = false
    @Published private(set) var talking = false

    private(set) var handle: Int = -1
    private(set) var talkHandle: Int = -1
    private var started = false

    var id: Int { channel }

    private var session: HikSession { HikSessions.shared.session(for: device) }

    init(device: Device, channel: Int) {
        self.device = device
        self.channel = channel
        canvas.onAttach = { [weak self] in self?.start() }
    }

    // MARK: 开流

    func start() {
        guard !started else { return }
        started = true
        status = "登录中…"
        failed = false
        attempt(retry: false)
    }

    private func attempt(retry: Bool) {
        let session = self.session
        let channel = self.channel

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var ok = session.ensureLogin(forceRelogin: retry)
            if !ok && !retry {
                // 失败自动清会话重登一次
                ok = session.ensureLogin(forceRelogin: true)
            }

            DispatchQueue.main.async {
                guard self.started else { return }
                guard ok else {
                    self.failed = true
                    self.status = session.lastError.isEmpty ? "登录失败" : session.lastError
                    return
                }
                let h = session.openLive(channel: channel, view: self.canvas.renderView)
                if h >= 0 {
                    self.handle = h
                    self.failed = false
                    self.status = ""
                    return
                }
                let err = HikMonSDK.lastErrorText()
                self.handle = -1
                if !retry {
                    // attempt(retry: true) 内部会在后台队列强制重登，别在主线程阻塞登录
                    self.status = "重试中…"
                    self.attempt(retry: true)
                } else {
                    self.failed = true
                    self.status = err
                }
            }
        }
    }

    func stop() {
        started = false
        if talking { stopTalk() }
        if soundOn {
            _ = HikMonSDK.closeSound()
            soundOn = false
        }
        if handle >= 0 {
            HikMonSDK.stopRealPlay(handle)
            handle = -1
        }
        status = "已停止"
    }

    func restart() {
        stop()
        started = false
        start()
    }

    deinit {
        if talkHandle >= 0 { HikMonSDK.stopVoiceTalk(talkHandle) }
        if handle >= 0 { HikMonSDK.stopRealPlay(handle) }
    }

    // MARK: 声音

    func toggleSound() {
        guard handle >= 0 else { return }
        if soundOn {
            _ = HikMonSDK.closeSound()
            soundOn = false
        } else if HikMonSDK.openSound(handle) {
            _ = HikMonSDK.setVolume(handle, volume: 80)
            soundOn = true
        } else {
            status = "开声音失败：\(HikMonSDK.lastErrorText())"
        }
    }

    // MARK: 对讲

    func startTalk() {
        guard !talking else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.talking = false
                    self.status = "没有麦克风权限，去 设置 → 隐私 → 麦克风 打开"
                }
                return
            }
            let session = self.session
            let channel = self.channel
            DispatchQueue.global(qos: .userInitiated).async {
                guard session.ensureLogin() else {
                    DispatchQueue.main.async { self.status = session.lastError }
                    return
                }
                let th = Int(HikMonSDK.startVoiceTalk(session.userId, channel: Int32(channel)))
                DispatchQueue.main.async {
                    if th >= 0 {
                        self.talkHandle = th
                        self.talking = true
                        self.status = ""
                    } else {
                        self.talking = false
                        self.status = "对讲失败：\(HikMonSDK.lastErrorText())"
                    }
                }
            }
        }
    }

    func stopTalk() {
        if talkHandle >= 0 {
            HikMonSDK.stopVoiceTalk(talkHandle)
            talkHandle = -1
        }
        talking = false
    }
}

// MARK: - 网格（2×2，最多 4 路一页）

final class LiveGrid: ObservableObject {
    let device: Device
    let players: [LivePlayer]

    init(device: Device) {
        self.device = device
        let chans = Array(device.channels.prefix(16))
        self.players = chans.map { LivePlayer(device: device, channel: $0) }
    }
}

// MARK: - 回放

final class PlaybackEngine: ObservableObject {
    let device: Device
    let canvas = SDKCanvasView()

    @Published private(set) var status = "选好时间后点「开始回放」"
    @Published private(set) var playing = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0

    private(set) var handle: Int = -1
    private var timer: Timer?

    private var session: HikSession { HikSessions.shared.session(for: device) }

    init(device: Device) { self.device = device }

    func start(channel: Int, from: Date, seconds: TimeInterval) {
        stop()
        duration = seconds
        position = 0
        status = "登录中…"

        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var ok = session.ensureLogin()
            if !ok { ok = session.ensureLogin(forceRelogin: true) }

            DispatchQueue.main.async {
                guard ok else {
                    self.status = session.lastError.isEmpty ? "登录失败" : session.lastError
                    return
                }
                let to = from.addingTimeInterval(seconds)
                let h = Int(HikMonSDK.startPlayback(session.userId,
                                                    channel: Int32(channel),
                                                    from: from,
                                                    to: to,
                                                    view: self.canvas.renderView))
                if h >= 0 {
                    self.handle = h
                    self.playing = true
                    self.status = ""
                    self.beginTimer()
                } else {
                    self.status = "回放失败：\(HikMonSDK.lastErrorText())"
                }
            }
        }
    }

    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard handle >= 0 else { return }
        let total = HikMonSDK.playbackTotalMillisecond(handle)
        if total > 0 { duration = Double(total) / 1000.0 }
        let pos = Double(HikMonSDK.playbackPositionMillisecond(handle)) / 1000.0
        if pos >= 0 { position = pos }
        if duration > 0 && position >= duration - 0.5 {
            stop()
            status = "播放结束"
        }
    }

    func togglePause() {
        guard handle >= 0 else { return }
        if playing {
            _ = HikMonSDK.playbackPause(handle)
            playing = false
        } else {
            _ = HikMonSDK.playbackResume(handle)
            playing = true
        }
    }

    func seek(to seconds: Double) {
        guard handle >= 0 else { return }
        position = max(0, min(seconds, duration))
        _ = HikMonSDK.playbackSeek(handle, toMillisecond: Int32(position * 1000))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if handle >= 0 {
            HikMonSDK.stopPlayback(handle)
            handle = -1
        }
        playing = false
    }

    deinit {
        timer?.invalidate()
        if handle >= 0 { HikMonSDK.stopPlayback(handle) }
    }
}
