import SwiftUI

struct DeviceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var device: Device
    private let isNew: Bool
    private let onSave: (Device) -> Void

    @State private var busy = false
    @State private var message = ""
    @State private var ok = false

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

    private func probeAndLoad() async {
        busy = true
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
}
