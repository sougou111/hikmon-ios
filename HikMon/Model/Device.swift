import Foundation

/// 与安卓 MainActivity.Dev 一一对应
struct Device: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 8000
    var user: String = "admin"
    var pass: String = ""
    var code: String = ""               // 码流加密验证码
    var talkChannel: Int = 0            // 语音通道号（0=未设置）
    var streamType: Int = 1             // 1=子码流 0=主码流
    var ipMode: Int = 0                 // 0=IPv4优先 1=仅IPv4 2=仅IPv6 3=IPv6优先
    var talkEnc: Int = 0                // 0=µ-law 1=A-law
    var talkChOverride: Int = 0
    var talkMode: Int = 1               // 1=仅监听 0=对讲+监听
    var isapiPort: Int = 80
    var favs: [Int] = []

    var key: String { "\(host):\(port):\(user)" }
    var label: String { name.isEmpty ? host : name }

    var streamTitle: String { streamType == 1 ? "子码流（省流量）" : "主码流（高清）" }

    var ipModeName: String {
        switch ipMode {
        case 1: return "仅 IPv4"
        case 2: return "仅 IPv6"
        case 3: return "IPv6 优先"
        default: return "IPv4 优先"
        }
    }

    static func normalizeHost(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = h.range(of: "^(?i)https?://", options: .regularExpression) { h.removeSubrange(r) }
        if let at = h.firstIndex(of: "@") { h = String(h[h.index(after: at)...]) }
        if let sl = h.firstIndex(of: "/") { h = String(h[..<sl]) }
        if h.hasPrefix("["), let close = h.firstIndex(of: "]") {
            h = String(h[h.index(after: h.startIndex)..<close])
        } else if h.filter({ $0 == ":" }).count == 1, let c = h.firstIndex(of: ":") {
            h = String(h[..<c])
        }
        return h.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = [] { didSet { save() } }

    private let key = "hikmon.devices.v3"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        devices = (try? JSONDecoder().decode([Device].self, from: data)) ?? []
    }

    func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ d: Device) { devices.append(d); save() }

    func update(_ d: Device) {
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d; save() }
    }

    func remove(id: UUID) {
        devices.removeAll { $0.id == id }
        save()
    }

    func byID(_ id: UUID?) -> Device? {
        guard let id else { return nil }
        return devices.first { $0.id == id }
    }

    func mutate(_ id: UUID, _ body: (inout Device) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        body(&devices[i])
        save()
    }
}
