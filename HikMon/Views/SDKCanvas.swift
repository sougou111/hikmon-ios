import UIKit
import SwiftUI

/// SDK 直渲染的画布：
/// - `renderView` 交给 HCNetSDK 当 hPlayWnd（SDK 自己往里画）
/// - 外面这层负责裁剪 + 手势（双指缩放 1–4×、单指拖动、双击复位）
final class SDKCanvasView: UIView {

    let renderView = UIView()

    /// 首次进入 window 时回调（SDK 必须等 view 有 layer/window 才能开流）
    var onAttach: (() -> Void)?
    var onSingleTap: (() -> Void)?

    var zoomEnabled = true

    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var startScale: CGFloat = 1
    private var startOffset: CGPoint = .zero

    private var didAttach = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true

        renderView.backgroundColor = .black
        renderView.isUserInteractionEnabled = false
        renderView.frame = bounds
        addSubview(renderView)
        installGestures()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didAttach else { return }
        didAttach = true
        DispatchQueue.main.async { [weak self] in self?.onAttach?() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderView.transform = .identity
        renderView.frame = bounds
        applyTransform()
    }

    // MARK: - 变换

    func resetZoom() {
        scale = 1
        offset = .zero
        applyTransform()
    }

    private func applyTransform() {
        renderView.transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
    }

    private func clampOffset() {
        let maxX = max(0, bounds.width * (scale - 1) / 2)
        let maxY = max(0, bounds.height * (scale - 1) / 2)
        offset.x = min(max(offset.x, -maxX), maxX)
        offset.y = min(max(offset.y, -maxY), maxY)
    }

    // MARK: - 手势

    private func installGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)

        addGestureRecognizer(pinch)
        addGestureRecognizer(pan)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(singleTap)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard zoomEnabled else { return }
        switch g.state {
        case .began:
            startScale = scale
        case .changed:
            scale = min(4, max(1, startScale * g.scale))
            clampOffset()
            applyTransform()
        case .ended, .cancelled, .failed:
            if scale <= 1.01 { resetZoom() }
        default: break
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard zoomEnabled, scale > 1 else { return }
        switch g.state {
        case .began:
            startOffset = offset
        case .changed:
            let t = g.translation(in: self)
            offset = CGPoint(x: startOffset.x + t.x, y: startOffset.y + t.y)
            clampOffset()
            applyTransform()
        default: break
        }
    }

    @objc private func handleDoubleTap() {
        guard zoomEnabled else { return }
        resetZoom()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }
}

/// 把 SDKCanvasView 塞进 SwiftUI（同一个实例，保证 SDK 渲染不被重建）
struct SDKCanvasRepresentable: UIViewRepresentable {
    let canvas: SDKCanvasView

    func makeUIView(context: Context) -> SDKCanvasView { canvas }
    func updateUIView(_ uiView: SDKCanvasView, context: Context) {}
}

/// 纯黑占位（没开流时显示）
struct VideoPlaceholder: View {
    var text: String

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 6) {
                ProgressView().tint(.white)
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }
}
