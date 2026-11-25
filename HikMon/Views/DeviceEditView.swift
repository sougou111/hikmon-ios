import SwiftUI

/// 新增 / 编辑合并成一个设置页
struct DeviceEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var device: Device
    private let isNew: Bool
    private let onSave: (Device) -> Void

    @State private var testing = false
    @State private var result = ""
    @State private var resultOK = false

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
                    TextField("地址：IP 或域名", text: $device.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Text("SDK 端口")
                        Spacer()
                        TextField("8000", value: $device.sdkPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("地址解析", selection: $device.resolveMode) {
                        ForEach(ResolveMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                }

                Section("账号") {
                    TextField("用户名", text: $device.user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $device.pass)
                }

                Section("取流") {
                    Toggle("使用子码流（省流量，多画面更流畅）", isOn: $device.useSubStream)
                    Stepper("通道数：\(device.channelCount)", value: $device.channelCount, in: 1...64)
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("测试登录", systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || device.host.isEmpty)

                    if !result.isEmpty {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(resultOK ? Color.green : Color.red)
                    }
                } header: {
                    Text("连通性")
                } footer: {
                    Text("测试会用 8000 端口做一次真实登录（NET_DVR_Login_V40），成功后会读出设备上报的通道数。")
                }

            }
            .navigationTitle(isNew ? "添加设备" : "设备设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(device)
                        dismiss()
                    }
                    .disabled(device.host.isEmpty)
                }
            }
        }
    }

    private func testConnection() {
        testing = true
        result = ""
        let snapshot = device

        DispatchQueue.global(qos: .userInitiated).async {
            HikMonSDK.globalInit()
            var host = snapshot.host
            if snapshot.resolveMode == .localDNS, let ip = HikMonSDK.resolveHost(snapshot.host) {
                host = ip
            }
            let uid = HikMonSDK.loginHost(host,
                                          port: Int32(snapshot.sdkPort),
                                          user: snapshot.user,
                                          password: snapshot.pass)
            guard uid >= 0 else {
                let err = HikMonSDK.lastErrorText()
                DispatchQueue.main.async {
                    self.testing = false
                    self.resultOK = false
                    self.result = "❌ \(err)"
                }
                return
            }
            let chans = Int(HikMonSDK.channelCount(uid))
            HikMonSDK.logout(uid)
            DispatchQueue.main.async {
                self.testing = false
                self.resultOK = true
                self.result = "✅ 登录成功，设备上报 \(chans) 个通道"
                if chans > 0 && chans > self.device.channelCount {
                    self.device.channelCount = chans
                }
            }
        }
    }
}
