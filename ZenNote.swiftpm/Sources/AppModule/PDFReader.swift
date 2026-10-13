import SwiftUI
import PDFKit
import PencilKit
import ZenNoteCore

@MainActor
struct PDFReader: UIViewControllerRepresentable {
    @ObservedObject var session: BookSession
    @ObservedObject var app: AppModel
    var presented = true

    func makeUIViewController(context: Context) -> PDFReaderController {
        let controller = PDFReaderController(session: session)
        controller.setPresented(presented)
        return controller
    }

    func updateUIViewController(_ controller: PDFReaderController, context: Context) {
        controller.setPresented(presented)
        controller.refreshInput()
    }

    static func dismantleUIViewController(_ controller: PDFReaderController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
final class PDFReaderController: UIViewController {
    let pdfView = PDFView()
    private let session: BookSession
    private let overlays: PDFOverlayProvider
    private var offsetObservation: NSKeyValueObservation?
    private var pageObserver: NSObjectProtocol?
    private var scaleObserver: NSObjectProtocol?
    private weak var scrollView: UIScrollView?
    private var tracking: DispatchWorkItem?
    private var fitScale: CGFloat = 1
    private var previousSize: CGSize = .zero
    private var restoring = true
    private var stopped = false
    private var presented = true
    private let readerID = UUID()

    init(session: BookSession) {
        self.session = session
        overlays = PDFOverlayProvider(session: session)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic controller") }

    override func loadView() {
        view = pdfView
        pdfView.backgroundColor = Theme.backgroundUI
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displayBox = .cropBox
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = false
        // Install the provider before the document; overlays are requested lazily.
        pdfView.pageOverlayViewProvider = overlays
        pdfView.document = session.document
        pdfView.documentView?.isUserInteractionEnabled = true
        pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.scheduleTracking() }
        }
        scaleObserver = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.scheduleTracking() }
        }
        session.attachReader(id: readerID,
            capture: { [weak self] in self?.capturePosition() },
            jump: { [weak self] page in self?.go(to: page) })
        pdfView.isUserInteractionEnabled = presented
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard presented, pdfView.bounds.width > 0, pdfView.bounds.height > 0, previousSize != pdfView.bounds.size else { return }
        let saved = session.state.readingPosition
        previousSize = pdfView.bounds.size
        attachScrollObservation()
        guard let page = session.document.page(at: saved.pageIndex) else { return }
        let box = page.bounds(for: .cropBox)
        let width = page.rotation % 180 == 0 ? box.width : box.height
        fitScale = max(0.05, (pdfView.bounds.width - 16) / max(1, width))
        pdfView.minScaleFactor = fitScale
        pdfView.maxScaleFactor = fitScale * 6
        restoring = true
        pdfView.scaleFactor = fitScale * CGFloat(saved.zoom)
        restore(saved)
        // PDFKit finishes its scroll geometry after the layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped, self.presented else { return }
            self.attachScrollObservation()
            self.restore(saved)
            self.restoring = false
            self.capturePosition()
        }
    }

    func setPresented(_ visible: Bool) {
        guard presented != visible else { return }
        if presented, isViewLoaded { capturePosition(); overlays.flush() }
        presented = visible
        tracking?.cancel()
        tracking = nil
        if isViewLoaded {
            pdfView.isUserInteractionEnabled = visible
            if visible { previousSize = .zero; view.setNeedsLayout() }
        }
    }

    func refreshInput() {
        guard isViewLoaded else { return }
        pdfView.isUserInteractionEnabled = presented
        pdfView.documentView?.isUserInteractionEnabled = true
        if let scrollView { configureFingerNavigation(scrollView, app: session.app) }
        overlays.refresh()
    }

    private func attachScrollObservation() {
        guard let found = findScroll(in: pdfView), scrollView !== found else { refreshInput(); return }
        scrollView = found
        offsetObservation = found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            // Explicitly enter the UI actor even if SDK observer annotations
            // describe this callback as nonisolated.
            DispatchQueue.main.async { [weak self] in self?.scheduleTracking() }
        }
        refreshInput()
    }

    private func findScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, !(scroll is PKCanvasView) { return scroll }
        for child in view.subviews {
            if let scroll = findScroll(in: child) { return scroll }
        }
        return nil
    }

    private func scheduleTracking() {
        guard presented, !restoring, !stopped, tracking == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.tracking = nil
            self?.capturePosition()
        }
        tracking = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func currentPosition() -> ReadingPosition? {
        guard pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return nil }
        let center = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        guard let page = pdfView.page(for: center, nearest: true) else { return nil }
        let index = session.document.index(for: page)
        guard index != NSNotFound else { return nil }
        let box = page.bounds(for: .cropBox)
        let point = pdfView.convert(center, to: page)
        return ReadingPosition(pageIndex: index,
            x: Double((point.x - box.minX) / max(1, box.width)),
            y: Double((point.y - box.minY) / max(1, box.height)),
            zoom: Double(pdfView.scaleFactor / max(0.05, fitScale)))
    }

    func capturePosition() {
        guard presented, !restoring, !stopped, let position = currentPosition() else { return }
        // The page crossing the PDF viewport's center is the active page.
        session.follow(position)
    }

    private func restore(_ position: ReadingPosition) {
        guard let page = session.document.page(at: position.pageIndex) else { return }
        let box = page.bounds(for: .cropBox)
        let point = CGPoint(x: box.minX + box.width * CGFloat(position.x), y: box.minY + box.height * CGFloat(position.y))
        pdfView.go(to: PDFDestination(page: page, at: point))
        pdfView.layoutIfNeeded()
        guard let scrollView else { return }
        let visiblePoint = pdfView.convert(point, from: page)
        let requested = CGPoint(
            x: scrollView.contentOffset.x + visiblePoint.x - pdfView.bounds.midX,
            y: scrollView.contentOffset.y + visiblePoint.y - pdfView.bounds.midY)
        let inset = scrollView.adjustedContentInset
        let maxX = max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        scrollView.setContentOffset(CGPoint(
            x: min(maxX, max(-inset.left, requested.x)),
            y: min(maxY, max(-inset.top, requested.y))), animated: false)
    }

    private func go(to index: Int) {
        guard let page = session.document.page(at: index) else { return }
        session.flushSurfaces()
        pdfView.go(to: page)
        capturePosition()
    }

    func stop() {
        guard !stopped else { return }
        capturePosition()
        overlays.flush()
        stopped = true
        tracking?.cancel()
        offsetObservation = nil
        if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
        if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) }
        pageObserver = nil
        scaleObserver = nil
        session.detachReader(id: readerID)
    }
}

@MainActor
private final class PDFOverlayProvider: NSObject, PDFPageOverlayViewProvider {
    private weak var session: BookSession?
    private var visible: [Int: DrawingSurface] = [:]

    init(session: BookSession) { self.session = session }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let session else { return nil }
        let index = session.document.index(for: page)
        guard index != NSNotFound else { return nil }
        if let existing = visible[index] { return existing }
        let overlay = DrawingSurface(session: session, target: .pdf(page: index))
        visible[index] = overlay
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        // PDFKit applies page geometry and rotation. Do not size the overlay
        // using screen coordinates or rewrite drawing coordinates at each zoom.
        pdfView.documentView?.isUserInteractionEnabled = true
        var ancestor = overlayView.superview
        while let view = ancestor, view !== pdfView {
            view.isUserInteractionEnabled = true
            ancestor = view.superview
        }
        (overlayView as? DrawingSurface)?.applySettings()
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        (overlayView as? DrawingSurface)?.flush()
        guard let session else { return }
        let index = session.document.index(for: page)
        if visible[index] === overlayView { visible.removeValue(forKey: index) }
    }

    func refresh() { for surface in visible.values { surface.applySettings() } }
    func flush() { for surface in visible.values { surface.flush() } }
}
