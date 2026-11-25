import Foundation
import UIKit
import SwiftUI

/// 回放引擎，对齐安卓 startPlaybackAsync / togglePlayPause / toggleSpeed：
/// 起播 = PlayBackByTime(起, 起+1h)；跳转 = 停掉重开（安卓也是这个做法）；
/// 播放/暂停、2× 走 PlayBackControl。
final class PbEngine: ObservableObject {
    let canvas = SDKCanvasView()

    @Published private(set) var tip = "回放准备中…"
    @Published private(set) var playing = false
    @Published private(set) var fast = false
    @Published private(set) var position: Double = 0     // 相对窗口起点秒数
    @Published private(set) var duration: Double = 3600  // 窗口长度

    private(set) var handle: Int = -1
    private var device: Device?
    private var channel: Int = 1
    private var base: Date = Date()
    private var timer: Timer?
    private var gen = 0

    func configure(device: Device, channel: Int, from: Date) {
        self.device = device
        self.channel = channel
        self.base = from
        self.position = 0
        self.duration = 3600
        self.fast = false
    }

    /// restart=false 时只起流；true 时先停旧句柄再按新基准起流（跳转）
    func start(restart: Bool) {
        guard let device else { return }
        gen += 1
        let myGen = gen
        if restart { stop(keepCanvas: true) }
        tip = "回放准备中…"
        playing = false

        let session = HikSessions.shared.session(for: device)
        let ch = channel
        let from = base
        let to = from.addingTimeInterval(duration)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard session.ensureLogin() >= 0 else {
                DispatchQueue.main.async { self.tip = "登录失败"; HikLog.shared.add("回放：登录失败") }
                return
            }
            DispatchQueue.main.async {
                guard myGen == self.gen else { return }
                HikLog.shared.add("回放请求 ch=\(ch) 起=\(Self.fmt(from))")
                let h = HikMonSDK.startPlayback(session.userId, channel: Int32(ch),
                                                from: from, to: to, view: self.canvas.renderView)
                if h >= 0 {
                    self.handle = h
                    self.tip = ""
                    self.playing = true
                    HikLog.shared.add("PlayBackByTime -> \(h)")
                    _ = HikMonSDK.makeKeyFrame(session.userId, channel: Int32(ch))
                    self.beginTimer()
                } else {
                    self.tip = "回放失败 \(HikMonSDK.lastErrorText())"
                    HikLog.shared.add("回放失败 \(HikMonSDK.lastErrorText())")
                }
            }
        }
    }

    func stop(keepCanvas: Bool = false) {
        timer?.invalidate()
        timer = nil
        playing = false
        if handle >= 0 {
            let h = handle
            handle = -1
            DispatchQueue.global(qos: .utility).async { HikMonSDK.stopPlayback(h) }
        }
        if !keepCanvas { tip = "回放准备中…" }
    }

    func togglePlayPause() {
        guard handle >= 0 else { start(restart: false); return }
        if playing {
            _ = HikMonSDK.playbackPause(handle)
            playing = false
        } else {
            _ = HikMonSDK.playbackResume(handle)
            playing = true
        }
    }

    func toggleSpeed() {
        guard handle >= 0 else { return }
        fast.toggle()
        _ = fast ? HikMonSDK.playbackFast(handle) : HikMonSDK.playbackNormal(handle)
        HikLog.shared.add("倍速 → \(fast ? "2×" : "1×")")
    }

    /// 时间轴拖动结束：按新时间点重开
    func seek(to date: Date) {
        base = date
        position = 0
        start(restart: true)
    }

    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.handle >= 0 else { return }
            let ms = HikMonSDK.playbackPositionMillisecond(self.handle)
            if ms > 0 { self.position = Double(ms) / 1000 }
        }
    }

    static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
