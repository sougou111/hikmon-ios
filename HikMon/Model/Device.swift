import Foundation

// MARK: - 地址解析模式

enum ResolveMode: String, Codable, CaseIterable, Identifiable {
    case direct      // 地址原样交给 SDK（IP 或设备自己能解析的名字）
    case localDNS    // 先在本机用 getaddrinfo 解析成 IP，再把 IP 交给 SDK

    var id: String { rawValue }
    var title: String {
        switch self {
        case .direct:   return "IP / 直连"
        case .localDNS: return "域名（本机解析）"
        }
    }
}

// MARK: - 通道

struct Camera: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var channel: Int
    var name: String
}

// MARK: - 设备

struct Device: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var sdkPort: Int = 8000
    var user: String = "admin"
    var pass: String = ""
    var useSubStream: Bool = false          // 主/子码流
    var resolveMode: ResolveMode = .direct
    var channelCount: Int = 4
    var cameras: [Camera] = []

    var title: String { name.isEmpty ? (host.isEmpty ? "未命名设备" : host) : name }

    var subtitle: String { "\(host):\(sdkPort) · \(user) · \(channelCount) 通道" }

    /// 网格要显示的通道号：优先用户配置的通道，否则 1…channelCount
    var channels: [Int] {
        if !cameras.isEmpty { return cameras.map(\.channel).sorted() }
        let n = max(1, channelCount)
        return Array(1...n)
    }

    func name(for channel: Int) -> String {
        cameras.first(where: { $0.channel == channel })?.name ?? "通道 \(channel)"
    }

    func streamTitle(_ ch: Int) -> String { "CH\(ch)" }
}

// MARK: - 本地存储

final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = [] { didSet { save() } }

    private let key = "hikmon.devices.v2"

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
    func remove(id: UUID) { devices.removeAll { $0.id == id } }
}
