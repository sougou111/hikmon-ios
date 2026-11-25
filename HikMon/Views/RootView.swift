import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var editing: Device?
    @State private var isNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.devices) { d in
                        NavigationLink {
                            LiveView(device: d)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.title).font(.headline)
                                Text(d.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                HikSessions.shared.drop(for: d)
                                store.remove(d)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                isNew = false
                                editing = d
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                } footer: {
                    Text(HikSDKInfo.available
                         ? "全部通过海康 HCNetSDK（8000 私有协议）取流，SDK 版本 \(HikSDKInfo.version)"
                         : "HCNetSDK 未编译进来（HAS_HIKSDK=0），当前只能看到界面，无法出图。")
                }
            }
            .navigationTitle("海康监控")
            .toolbar {
                Button {
                    isNew = true
                    editing = Device()
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(item: $editing) { d in
                DeviceEditView(device: d, isNew: isNew) { saved in
                    if isNew {
                        store.add(saved)
                    } else {
                        store.update(saved)
                        HikSessions.shared.drop(for: saved)
                    }
                }
            }
            .overlay {
                if store.devices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.metering.unknown")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("还没有设备").font(.headline)
                        Text("右上角 + 添加 NVR / 摄像机（地址、8000 端口、账号）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                }
            }
        }
    }
}
