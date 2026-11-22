import SwiftUI
import Photos

// MARK: - 实时预览

struct LiveView: View {
    let device: Device

    @State private var cameras: [Camera]
    @State private var fullscreen: Camera?
    @State private var loading = false
    @State private var err = ""
    @State private var showPlayback = false

    init(device: Device) {
        self.device = device
        _cameras = State(initialValue: device.cameras)
    }

    private var columns: [GridItem] {
        cameras.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    }

    var body: some View {
        ScrollView {
            if cameras.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.unknown").font(.largeTitle).foregroundStyle(.secondary)
                    Text("还没有通道").font(.headline)
                    Text("点右上角刷新，从设备读取通道列表").font(.caption).foregroundStyle(.secondary)
                    Button("刷新通道") { Task { await loadChannels() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(cameras) { cam in
                        CameraCell(device: device, camera: cam)
                            .onTapGesture { fullscreen = cam }
                    }
                }
                .padding(6)
            }

            if !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(.red).padding()
            }
        }
        .navigationTitle(device.name.isEmpty ? device.host : device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showPlayback = true } label: { Image(systemName: "clock.arrow.circlepath") }
                Button {
                    Task { await loadChannels() }
                } label: {
                    if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .sheet(item: $fullscreen) { cam in
            FullscreenLive(device: device, camera: cam)
        }
        .sheet(isPresented: $showPlayback) {
            PlaybackView(device: device, cameras: cameras)
        }
        .task {
            if cameras.isEmpty { await loadChannels() }
        }
    }

    private func loadChannels() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await ISAPIClient(device: device).channels()
            if list.isEmpty {
                err = "设备没有返回通道（可能是 IPC：试试直接填通道 1）"
            } else {
                cameras = list
                err = ""
            }
        } catch {
            err = "读取通道失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 单画面格子

struct CameraCell: View {
    let device: Device
    let camera: Camera
    @StateObject private var box = PlayerBox()

    var body: some View {
        ZStack {
            VLCVideoView(player: box.player)
            if !box.isPlaying {
                VStack(spacing: 6) {
                    if box.failed {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(box.stateText).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("CH\(camera.channel) 连接中").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            VStack {
                HStack {
                    Text("CH\(camera.channel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(6)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { box.play(device.liveURL(channel: camera.channel)) }
        .onDisappear { box.stop() }
    }
}

// MARK: - 全屏 + 云台 + 抓图

struct FullscreenLive: View {
    let device: Device
    let camera: Camera
    @Environment(\.dismiss) private var dismiss
    @StateObject private var box = PlayerBox()
    @State private var toast = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCVideoView(player: box.player).ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").padding(10).background(.black.opacity(0.5)).clipShape(Circle())
                    }
                    Text("CH\(camera.channel) \(camera.name)")
                        .font(.subheadline).lineLimit(1)
                    Spacer()
                    Button { Task { await snap() } } label: {
                        Image(systemName: "camera").padding(10).background(.black.opacity(0.5)).clipShape(Circle())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)

                Spacer()

                if !toast.isEmpty {
                    Text(toast).font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.6)).foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                PTZPad(device: device, channel: camera.channel)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { box.play(device.liveURL(channel: camera.channel)) }
        .onDisappear { box.stop() }
    }

    private func snap() async {
        do {
            let data = try await ISAPIClient(device: device).snapshot(channel: camera.channel)
            guard let img = UIImage(data: data) else { toast = "抓图数据无效"; return }
            let ok = await PhotoSaver.save(img)
            toast = ok ? "已保存到相册" : "保存失败（检查相册权限）"
        } catch {
            toast = "抓图失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 云台

struct PTZPad: View {
    let device: Device
    let channel: Int

    var body: some View {
        VStack(spacing: 8) {
            ptzButton("chevron.up", pan: 0, tilt: 1)
            HStack(spacing: 8) {
                ptzButton("chevron.left", pan: -1, tilt: 0)
                Button {
                    send(pan: 0, tilt: 0, zoom: 0)
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                ptzButton("chevron.right", pan: 1, tilt: 0)
            }
            ptzButton("chevron.down", pan: 0, tilt: -1)
            HStack(spacing: 24) {
                ptzButton("minus.magnifyingglass", pan: 0, tilt: 0, zoom: -1)
                ptzButton("plus.magnifyingglass", pan: 0, tilt: 0, zoom: 1)
            }
        }
        .foregroundStyle(.white)
    }

    private func ptzButton(_ icon: String, pan: Int, tilt: Int, zoom: Int = 0) -> some View {
        Button {
            send(pan: pan, tilt: tilt, zoom: zoom)
        } label: {
            Image(systemName: icon)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private func send(pan: Int, tilt: Int, zoom: Int) {
        Task { await ISAPIClient(device: device).ptz(channel: channel, pan: pan, tilt: tilt, zoom: zoom) }
    }
}

// MARK: - 相册保存

enum PhotoSaver {
    static func save(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        guard let data = image.jpegData(compressionQuality: 0.95) else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            return false
        }
    }
}
