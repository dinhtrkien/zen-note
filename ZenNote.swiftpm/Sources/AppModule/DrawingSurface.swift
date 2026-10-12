import UIKit
import PencilKit
import ZenNoteCore

@MainActor
final class DrawingSurface: UIView, PKCanvasViewDelegate {
    let canvas = PKCanvasView()
    let target: DrawingTarget
    private weak var session: BookSession?
    private var pendingSave: DispatchWorkItem?
    private var dirty = false
    private var loadFailed = false

    init(session: BookSession, target: DrawingTarget) {
        self.session = session
        self.target = target
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.panGestureRecognizer.isEnabled = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.clipsToBounds = true
        do { canvas.drawing = try session.drawing(for: target) }
        catch {
            loadFailed = true
            session.app.issue = "Could not read this drawing: \(error.localizedDescription) Its file has not been replaced; editing this surface is disabled."
        }
        canvas.delegate = self
        addSubview(canvas)
        session.register(self)
        applySettings()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        canvas.contentSize = bounds.size
    }

    func applySettings() {
        guard let session else { return }
        let app = session.app
        canvas.tool = app.settings.pencilTool
        canvas.drawingPolicy = app.settings.input == .stylus ? .pencilOnly : .anyInput
        canvas.drawingGestureRecognizer.isEnabled = !app.navigating && !loadFailed
        // Keep view interaction enabled: ancestors must still receive scrolling
        // and pinching. Do not toggle canvas.isUserInteractionEnabled here.
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        session?.focus(self)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !loadFailed else { return }
        dirty = true
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        session?.updateUndo()
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        // Save completed strokes promptly; also allow the final delegate change
        // notification to arrive before serializing the drawing.
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty, !loadFailed else { return }
        dirty = false
        // The target was captured at creation. A delayed stroke can never be
        // saved against whichever PDF page happens to be active later.
        session?.saveDrawing(canvas.drawing, target: target)
    }
}

@MainActor
final class PaperView: UIView {
    var paper: PaperStyle = .grid { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    override func draw(_ rect: CGRect) {
        guard paper == .grid, let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor(red: 0.81, green: 0.86, blue: 0.89, alpha: 1).cgColor)
        context.setLineWidth(0.5)
        let spacing: CGFloat = 24
        var x = floor(rect.minX / spacing) * spacing
        while x <= rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = floor(rect.minY / spacing) * spacing
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        context.strokePath()
    }
}

@MainActor
func configureFingerNavigation(_ scroll: UIScrollView, app: AppModel) {
    let touches = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    scroll.panGestureRecognizer.allowedTouchTypes = touches
    scroll.pinchGestureRecognizer?.allowedTouchTypes = touches
    scroll.panGestureRecognizer.minimumNumberOfTouches = app.settings.input == .compatible && !app.navigating ? 2 : 1
}
