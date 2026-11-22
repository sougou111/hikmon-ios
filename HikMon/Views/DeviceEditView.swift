import SwiftUI

struct DeviceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var device: Device
    private let isNew: Bool
    private let onSave: (Device) -> Void

    @State private var busy = false
    @State private var message = ""
    @State private var ok = false
    @State private var diagBusy = false
    @State private var diagLines: [String] = []

    init(device: Device, isNew: Bool, onSave: @escaping (Device) -> Void) {
        _device = State(initialValue: device)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("设备") {
                    TextField("名称（可选）", text: $device.name)
                    TextField("IP / 域名", text: $device.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text("ISAPI 端口")
                        Spacer()
                        TextField("80", value: $device.isapiPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("RTSP 端口")
                        Spacer()
                        TextField("554", value: $device.rtspPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("账号") {
                    TextField("用户名", text: $device.user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $device.pass)
                }

                Section {
                    Toggle("使用子码流（省流量、多画面更稳）", isOn: $device.useSubStream)
                }

                Section("通道") {
                    if device.cameras.isEmpty {
                        Text("点下面「拉取通道」从设备读取，也可以先保存，进实时页再拉。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(device.cameras) { c in
                            HStack {
                                Text("CH\(c.channel)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(c.name)
                            }
                        }
                    }
                    Button {
                        Task { await probeAndLoad() }
                    } label: {
                        HStack {
                            Label("拉取通道", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(busy || device.host.isEmpty)
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(ok ? Color.green : Color.red)
                    }
                }

                Section {
                    Button {
                        Task { await diagnose() }
                    } label: {
                        HStack {
                            Label("端口诊断（扫端口 + 试 RTSP）", systemImage: "stethoscope")
                            Spacer()
                            if diagBusy { ProgressView() }
                        }
                    }
                    .disabled(diagBusy || device.host.isEmpty)
                    ForEach(diagLines, id: \.self) { line in
                        Text(line).font(.caption)
                    }
                } header: {
                    Text("诊断")
                } footer: {
                    Text("海康端口分工：80 = ISAPI(HTTP)、554 = RTSP、8000 = SDK 私有协议。iVMS 4500+ 用的是 8000 那条私有通道，本 App 必须能访问 80 和 554。")
                }
            }
            .navigationTitle(isNew ? "添加设备" : "编辑设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(device); dismiss() }
                        .disabled(device.host.isEmpty)
                }
            }
        }
    }

    private func probeAndLoad() async {        busy = true
        message = ""
        defer { busy = false }
        let api = ISAPIClient(device: device)
        do {
            let info = try await api.deviceInfo()
            let cam = try await api.channels()
            device.cameras = cam
            var parts: [String] = []
            if !info.name.isEmpty { parts.append(info.name) }
            if !info.model.isEmpty { parts.append(info.model) }
            if !info.firmware.isEmpty { parts.append("固件 \(info.firmware)") }
            parts.append("\(cam.count) 个通道")
            message = parts.joined(separator: " · ")
            ok = true
        } catch {
            message = "连接失败：\(error.localizedDescription)"
            ok = false
        }
    }

    /// 端口诊断：先扫常用端口，再分别验证 ISAPI 与 RTSP
    private func diagnose() async {
        diagBusy = true
        diagLines = []
        defer { diagBusy = false }

        let open = await Prober.scan(host: device.host)
        if open.isEmpty {
            diagLines.append("❌ 常用端口（80/8000/554/8080/443…）都连不上")
        } else {
            diagLines.append("✅ 开放端口：" + open.map(String.init).joined(separator: "、"))
        }
        if open.contains(8000) && !open.contains(80) {
            diagLines.append("→ 只开了 8000：那是海康 SDK 私有口，iVMS 4500+ 走这条；本 App 需要 80/554")
        }

        let rt = await Prober.rtsp(host: device.host, port: device.rtspPort)
        diagLines.append((rt.ok ? "✅ " : "❌ ") + "RTSP \(device.rtspPort)：\(rt.note)")

        do {
            let info = try await ISAPIClient(device: device).deviceInfo()
            diagLines.append("✅ ISAPI \(device.isapiPort)：\(info.model.isEmpty ? info.name : info.model)")
        } catch {
            diagLines.append("❌ ISAPI \(device.isapiPort)：\(error.localizedDescription)")
        }
    }
}
