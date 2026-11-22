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
                                Text(d.name.isEmpty ? d.host : d.name).font(.headline)
                                Text("\(d.host):\(d.isapiPort) · RTSP \(d.rtspPort) · \(d.cameras.count) 通道")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.remove(d) } label: { Label("删除", systemImage: "trash") }
                            Button { isNew = false; editing = d } label: { Label("编辑", systemImage: "pencil") }
                                .tint(.blue)
                        }
                    }
                } footer: {
                    Text("只走海康 ISAPI + 标准 RTSP，不依赖任何厂商 SDK。")
                }
            }
            .navigationTitle("海康监控")
            .toolbar {
                Button {
                    isNew = true
                    editing = Device(name: "", host: "")
                } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { d in
                DeviceEditView(device: d, isNew: isNew) { saved in
                    if isNew { store.add(saved) } else { store.update(saved) }
                }
            }
            .overlay {
                if store.devices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.metering.unknown").font(.largeTitle).foregroundStyle(.secondary)
                        Text("还没有设备").font(.headline)
                        Text("右上角 + 添加 NVR / 摄像机（IP、端口、账号）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
