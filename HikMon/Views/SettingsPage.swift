import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    @State private var promptTitle = ""
    @State private var promptText = ""
    @State private var promptVisible = false
    @State private var promptApply: ((String) -> Void)?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let d = store.byID(state.settingsDev) {
                content(d)
            } else {
                EmptyHint(text: "设备不存在")
            }
        }
        .alert(promptTitle, isPresented: $promptVisible) {
            TextField("", text: $promptText)
            Button("保存") { promptApply?(promptText.trimmingCharacters(in: .whitespaces)) }
            Button("取消", role: .cancel) {}
        }
    }

    private func content(_ d: Device) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "连接参数")

                row("名称", d.label) { ask("设备名称", d.name) { s in
                    store.mutate(d.id) { $0.name = s }
                } }
                row("地址", d.host) { ask("IP / 域名", d.host) { s in
                    guard !s.isEmpty else { return }
                    HikSessions.shared.drop(for: d)
                    store.mutate(d.id) { $0.host = Device.normalizeHost(s) }
                } }
                row("SDK 端口", String(d.port)) { ask("端口（海康默认 8000）", String(d.port)) { s in
                    guard let p = Int(s) else { return }
                    HikSessions.shared.drop(for: d)
                    store.mutate(d.id) { $0.port = p }
                } }
                row("用户名", d.user) { ask("用户名", d.user) { s in
                    guard !s.isEmpty else { return }
                    HikSessions.shared.drop(for: d)
                    store.mutate(d.id) { $0.user = s }
                } }
                row("密码", d.pass.isEmpty ? "（空）" : "已设置  ·  点击修改") { ask("密码", d.pass) { s in
                    HikSessions.shared.drop(for: d)
                    store.mutate(d.id) { $0.pass = s }
                } }

                SectionTitle(text: "画面")
                row("码流", d.streamTitle) {
                    store.mutate(d.id) { $0.streamType = ($0.streamType == 1) ? 0 : 1 }
                    HikLog.shared.add("\(d.label) 码流 → \(d.streamType == 1 ? "主码流" : "子码流")")
                }

                SectionTitle(text: "网络")
                row("地址解析", d.ipModeName) {
                    HikSessions.shared.drop(for: d)
                    store.mutate(d.id) { $0.ipMode = ($0.ipMode + 1) % 4 }
                    let nd = store.byID(d.id)
                    HikLog.shared.add("\(d.label) 网络模式 → \(nd?.ipModeName ?? "")")
                }

                SectionTitle(text: "诊断")
                row("读取设备配置", "只读") {
                    state.diagDev = d.id
                    state.go(.diag)
                }

                SectionTitle(text: "危险操作")
                Button {
                    confirmDelete = true
                } label: {
                    Text("删除这台服务器")
                        .font(.system(size: 14))
                        .foregroundStyle(C.dangerText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(C.dangerBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(C.dangerEdge, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .alert("删除服务器", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { deleteDevice() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(d.label)」？")
        }
    }

    private func deleteDevice() {
        guard let d = store.byID(state.settingsDev) else { return }
        HikSessions.shared.drop(for: d)
        store.remove(id: d.id)
        HikLog.shared.add("已删除 \(d.label)")
        state.settingsDev = nil
        state.go(.devices)
    }

    private func row(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(C.text)
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(C.accent)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(C.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(C.stroke, lineWidth: 1)
                    )
            )
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }

    private func ask(_ title: String, _ cur: String, apply: @escaping (String) -> Void) {
        promptTitle = title
        promptText = cur
        promptApply = apply
        promptVisible = true
    }
}
