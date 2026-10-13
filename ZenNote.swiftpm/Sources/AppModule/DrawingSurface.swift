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
    private var appliedSettings: DrawingSettings?
    private var strokeGeneration = 0

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
        let settings = app.settings
        // Activity/zoom updates also refresh representables. Do not reset the
        // active PencilKit tool on every redraw or midway through a stroke.
        if appliedSettings?.tool != settings.tool || appliedSettings?.activeInk != settings.activeInk || appliedSettings?.width != settings.width {
            canvas.tool = settings.pencilTool
        }
        if settings.input == .stylus {
            if canvas.drawingPolicy != .pencilOnly { canvas.drawingPolicy = .pencilOnly }
        } else if canvas.drawingPolicy != .anyInput { canvas.drawingPolicy = .anyInput }
        appliedSettings = settings
        let paneVisible: Bool
        switch target {
        case .pdf: paneVisible = app.settings.layout != .notes
        case .note: paneVisible = app.settings.layout != .textbook
        }
        let enabled = session.acceptsDrawing && paneVisible && !app.navigating && !loadFailed
        if canvas.drawingGestureRecognizer.isEnabled != enabled { canvas.drawingGestureRecognizer.isEnabled = enabled }
        // Keep view interaction enabled: ancestors must still receive scrolling
        // and pinching. Do not toggle canvas.isUserInteractionEnabled here.
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { flush(); session?.endStroke(self) }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        strokeGeneration &+= 1
        session?.beginStroke(self)
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
        let generation = strokeGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flush()
            if self.strokeGeneration == generation { self.session?.endStroke(self) }
        }
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
    var paper: PaperStyle = .grid { didSet { if oldValue != paper { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.paperUI
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    override func draw(_ rect: CGRect) {
        guard paper != .blank, let context = UIGraphicsGetCurrentContext() else { return }
        let spacing: CGFloat = 24
        if paper == .dotted {
            context.setFillColor(Theme.gridUI.cgColor)
            var y = floor(rect.minY / spacing) * spacing
            while y <= rect.maxY {
                var x = floor(rect.minX / spacing) * spacing
                while x <= rect.maxX {
                    context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += spacing
                }
                y += spacing
            }
            return
        }
        context.setStrokeColor(Theme.gridUI.cgColor)
        context.setLineWidth(0.5)
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
