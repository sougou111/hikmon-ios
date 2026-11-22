import Foundation

// MARK: - 数据模型

struct Camera: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var channel: Int          // NVR/IPC 上的通道号，从 1 开始
    var name: String
}

struct Device: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String            // IP 或域名
    var isapiPort: Int = 80
    var rtspPort: Int = 554
    var sdkPort: Int = 8000     // 海康 SDK 私有协议端口（iVMS 4500+ 用的就是它）
    var user: String = "admin"
    var pass: String = ""
    var useSubStream: Bool = false
    var cameras: [Camera] = []

    /// 海康 RTSP 通道编号：通道 1 主码流 = 101，子码流 = 102
    func streamID(_ channel: Int, sub: Bool) -> Int {
        channel * 100 + (sub ? 2 : 1)
    }

    var isapiBase: String {
        let scheme = isapiPort == 443 ? "https" : "http"
        return "\(scheme)://\(host):\(isapiPort)"
    }

    private func encoded(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? s
    }

    /// 实时预览
    func liveURL(channel: Int) -> String {
        let id = streamID(channel, sub: useSubStream)
        return "rtsp://\(encoded(user)):\(encoded(pass))@\(host):\(rtspPort)/Streaming/Channels/\(id)"
    }

    /// 回放：两天内的任意时间段，海康用 tracks 接口
    func playbackURL(channel: Int, from: Date, to: Date) -> String {
        let id = streamID(channel, sub: false)
        return "rtsp://\(encoded(user)):\(encoded(pass))@\(host):\(rtspPort)/Streaming/tracks/\(id)?starttime=\(Self.hikTime(from))&endtime=\(Self.hikTime(to))"
    }

    /// 海康时间格式：20261122T101500Z（UTC）
    static func hikTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }
}

// MARK: - 本地存储

final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = [] { didSet { save() } }

    private let key = "hikmon.devices.v1"

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        devices = (try? JSONDecoder().decode([Device].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ d: Device) { devices.append(d) }

    func update(_ d: Device) {
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d }
    }

    func remove(_ d: Device) { devices.removeAll { $0.id == d.id } }
}
