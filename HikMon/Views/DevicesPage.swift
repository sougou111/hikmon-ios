import SwiftUI

struct DevicesPage: View {
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var state: AppState

    @State private var name = ""
    @State private var host = ""
    @State private var port = "8000"
    @State private var user = "admin"
    @State private var pass = ""
    @State private var code = ""

    private var formOpen: Bool { state.showAddForm || state.editID != nil }
    private var editing: Device? { store.byID(state.editID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if formOpen { form }

                SectionTitle(text: "已保存的服务器")

                if store.devices.isEmpty {
                    HintLine(text: "还没有服务器，点下面的「添加服务器」")
                }

                ForEach(store.devices) { d in
                    card(d)
                        .padding(.bottom, 10)
                }

                if !formOpen {
                    Button {
                        state.showAddForm = true
                        state.editID = nil
                        fill(nil)
                    } label: {
                        Chip(text: "＋ 添加服务器", primary: true, stretch: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .onAppear { fill(editing) }
        .onChange(of: state.editID) { _ in fill(editing) }
        .onChange(of: state.showAddForm) { on in if on { fill(nil) } }
    }

    // MARK: 表单

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(editing != nil ? "正在编辑：\(editing!.label)" : "新增服务器")
                    .font(.system(size: 13))
                    .foregroundStyle(C.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChipButton(text: "取消") {
                    state.showAddForm = false
                    state.editID = nil
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(C.banner)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(C.accent, lineWidth: 1)
                    )
            )
            .padding(.bottom, 12)

            HikField(placeholder: "名称（例如：门店A）", text: $name)
            HikField(placeholder: "主机地址 / 域名", text: $host)
            HikField(placeholder: "端口（海康默认 8000）", text: $port, keyboard: .numberPad)
            HikField(placeholder: "用户名", text: $user)
            HikField(placeholder: "密码", text: $pass, secure: true)
            HikField(placeholder: "验证码（码流加密时填）", text: $code)

            Button(action: save) {
                Chip(text: editing != nil ? "保存修改" : "保存并添加", primary: true, stretch: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func fill(_ d: Device?) {
        name = d?.name ?? ""
        host = d?.host ?? ""
        port = String(d?.port ?? 8000)
        user = d?.user.isEmpty == false ? d!.user : "admin"
        pass = d?.pass ?? ""
        code = d?.code ?? ""
    }

    private func save() {
        let h = Device.normalizeHost(host)
        guard !h.isEmpty else { state.show("主机地址不能为空"); return }
        let p = Int(port.trimmingCharacters(in: .whitespaces)) ?? 8000
        if let old = editing {
            HikSessions.shared.drop(for: old)
            var d = old
            d.name = name.trimmingCharacters(in: .whitespaces)
            d.host = h
            d.port = p
            d.user = user.trimmingCharacters(in: .whitespaces)
            d.pass = pass
            d.code = code.trimmingCharacters(in: .whitespaces).uppercased()
            store.update(d)
            HikLog.shared.add("已修改 \(d.label)")
        } else {
            var d = Device()
            d.name = name.trimmingCharacters(in: .whitespaces)
            d.host = h
            d.port = p
            d.user = user.trimmingCharacters(in: .whitespaces)
            d.pass = pass
            d.code = code.trimmingCharacters(in: .whitespaces).uppercased()
            store.add(d)
            HikLog.shared.add("已添加 \(d.label)")
        }
        state.showAddForm = false
        state.editID = nil
    }

    // MARK: 已保存服务器卡片

    private func card(_ d: Device) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(d.label)
                .font(.system(size: 16))
                .foregroundStyle(C.text)
            Text(subLine(d))
                .font(.system(size: 11))
                .foregroundStyle(C.sub)
                .padding(.top, 4)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                ChipButton(text: "通道管理", primary: true) {
                    state.channelDev = d.id
                    state.go(.channels)
                }
                ChipButton(text: "设置") {
                    state.settingsDev = d.id
                    state.go(.settings)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(C.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(C.stroke, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            state.editID = d.id
            state.showAddForm = false
            fill(d)
        }
    }

    private func subLine(_ d: Device) -> String {
        var s = "\(d.host):\(d.port)   \(d.user)   收藏 \(d.favs.count) 路"
        if d.talkChannel > 0 { s += "   音频通道 \(d.talkChannel)" }
        if let addr = HikSessions.shared.session(for: d).lastAddr.isEmpty ? nil : HikSessions.shared.session(for: d).lastAddr {
            s += "\n当前地址 \(addr)"
        }
        return s
    }
}


