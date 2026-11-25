import Foundation
import AVFoundation

/// 语音对讲 / 监听：
/// 设备侧走 NET_DVR_StartVoiceCom_MR_V30（回调给 G.711），本机侧 AVAudioEngine
/// 采 8k 单声道 → G.711 编码 → NET_DVR_VoiceComSendData；收到的帧解码成 PCM 播放。
final class TalkEngine {
    static let shared = TalkEngine()

    private(set) var handle: Int = -1
    private(set) var deviceKey: String = ""
    private(set) var channel: Int = 0
    private(set) var sending = false

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var converter: AVAudioConverter?
    private let fmt8k: AVAudioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                     sampleRate: 8000,
                                                     channels: 1,
                                                     interleaved: true)!
    private var aLaw = false
    private var sentBytes = 0
    private var recvCount = 0
    private var pending = [UInt8]()
    private let audioQ = DispatchQueue(label: "com.ynvr.hikmon.talk")

    var isRunning: Bool { handle >= 0 }

    // MARK: - 开始

    @discardableResult
    func start(device: Device, channel: Int, send: Bool) -> Bool {
        stop()

        let session = HikSessions.shared.session(for: device)
        guard session.ensureLogin() >= 0 else {
            HikLog.shared.add("对讲失败：登录失败 \(session.lastError)")
            return false
        }

        aLaw = device.talkEnc == 1
        let audioCh = device.talkChOverride > 0 ? device.talkChOverride
                                                : (device.talkChannel > 0 ? device.talkChannel : channel)
        HikLog.shared.add("对讲参数：音频通道=\(audioCh) 编码=\(aLaw ? "A-law" : "µ-law") 模式=\(send ? "对讲+监听" : "仅监听")")

        let h = HikMonSDK.startVoiceCom(session.userId, channel: Int32(audioCh)) { [weak self] data, flag in
            self?.onVoiceData(data, flag: flag)
        }
        guard h >= 0 else {
            HikLog.shared.add("对讲失败 \(HikMonSDK.lastErrorText())")
            return false
        }
        handle = h
        deviceKey = device.key
        self.channel = audioCh
        sending = send
        recvCount = 0
        sentBytes = 0

        startAudio(send: send)
        HikLog.shared.add("对讲已开启 \(device.label) 通道 \(audioCh) handle=\(h)")
        return true
    }

    func stop() {
        if handle >= 0 {
            HikMonSDK.stopVoiceCom(handle)
            HikLog.shared.add("对讲已关闭")
        }
        handle = -1
        deviceKey = ""
        sending = false
        stopAudio()
    }

    // MARK: - 音频链路

    private func startAudio(send: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            HikLog.shared.add("音频会话设置失败 \(error.localizedDescription)")
        }

        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: fmt8k)
        node.play()

        if send {
            let input = eng.inputNode
            let inFmt = input.inputFormat(forBus: 0)
            if inFmt.sampleRate > 0,
               let conv = AVAudioConverter(from: inFmt, to: fmt8k) {
                converter = conv
                input.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { [weak self] buf, _ in
                    self?.handleMic(buffer: buf, inputFormat: inFmt)
                }
            } else {
                HikLog.shared.add("麦克风不可用，改为仅监听")
                sending = false
            }
        }

        do {
            eng.prepare()
            try eng.start()
            engine = eng
            player = node
        } catch {
            HikLog.shared.add("音频引擎启动失败 \(error.localizedDescription)")
        }
    }

    private func stopAudio() {
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
        engine = nil
        player = nil
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 上行（麦克风 → G.711）

    private func handleMic(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard sending, handle >= 0, let conv = converter else { return }

        let ratio = fmt8k.sampleRate / inputFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt8k, frameCapacity: cap) else { return }

        var err: NSError?
        var fed = false
        let status = conv.convert(to: out, error: &err) { _, st in
            if fed { st.pointee = .noDataNow; return nil }
            fed = true
            st.pointee = .haveData
            return buffer
        }
        guard err == nil, status != .error, out.frameLength > 0,
              let ch = out.int16ChannelData else { return }

        let n = Int(out.frameLength)
        let enc = G711.encode(ch[0], count: n, aLaw: aLaw)
        audioQ.async { [weak self] in
            guard let self = self, self.handle >= 0 else { return }
            self.pending.append(contentsOf: enc)
            // 20ms 一包（160 样本）发出去，和安卓节奏一致
            while self.pending.count >= 160 {
                let chunk = Array(self.pending.prefix(160))
                self.pending.removeFirst(160)
                _ = HikMonSDK.sendVoiceData(self.handle, data: Data(chunk))
                self.sentBytes += chunk.count
                if self.sentBytes == chunk.count {
                    HikLog.shared.add("语音开始上行（\(self.aLaw ? "A-law" : "µ-law")）")
                }
            }
        }
    }

    // MARK: - 下行（设备 G.711 → 播放）

    private func onVoiceData(_ data: Data, flag: Int32) {
        guard handle >= 0 else { return }
        recvCount += 1
        if recvCount == 1 {
            HikLog.shared.add("收到设备音频首帧 \(data.count)B flag=\(flag)")
        }
        let bytes = [UInt8](data)
        let pcm = G711.decode(bytes, aLaw: aLaw)
        guard !pcm.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: fmt8k, frameCapacity: AVAudioFrameCount(pcm.count)) else { return }
        buf.frameLength = AVAudioFrameCount(pcm.count)
        if let dst = buf.int16ChannelData {
            pcm.withUnsafeBufferPointer { src in
                dst[0].update(from: src.baseAddress!, count: pcm.count)
            }
        }
        player?.scheduleBuffer(buf, completionHandler: nil)
    }
}
