import SwiftUI

/// 一格画面（安卓 Cell）：黑底 + SDK 渲染 + 中间提示 + 右上角 ⛶
struct CellView: View {
    @ObservedObject var cell: LiveCell
    var showFull: Bool = false
    var onFull: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onLong: (() -> Void)? = nil

    var body: some View {
        ZStack {
            SDKCanvasRepresentable(canvas: cell.canvas)
                .background(C.cellBg)

            if !cell.live && !cell.tip.isEmpty {
                Text(cell.tip)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x7C8697))
                    .multilineTextAlignment(.center)
                    .padding(6)
            }

            if showFull {
                VStack {
                    HStack {
                        Spacer()
                        Button { onFull?() } label: {
                            Text("⛶")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.cellEdge, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onLongPressGesture(minimumDuration: 0.6) { onLong?() }
    }
}

/// 视频画布 + 手势（单通道/回放用，支持缩放拖动）
struct VideoPane: View {
    let canvas: SDKCanvasView
    var tip: String
    var onTap: (() -> Void)? = nil
    var onLong: (() -> Void)? = nil

    var body: some View {
        ZStack {
            SDKCanvasRepresentable(canvas: canvas)
                .background(C.cellBg)
            if !tip.isEmpty {
                Text(tip)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x7C8697))
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(C.cellEdge, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onLongPressGesture(minimumDuration: 0.6) { onLong?() }
    }
}
