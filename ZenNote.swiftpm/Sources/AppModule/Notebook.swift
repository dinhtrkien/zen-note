import SwiftUI
import UIKit
import ZenNoteCore

@MainActor
struct Notebook: UIViewControllerRepresentable {
    @ObservedObject var session: BookSession
    @ObservedObject var app: AppModel
    var presented = true

    func makeUIViewController(context: Context) -> NotebookController {
        let controller = NotebookController(session: session)
        controller.setPresented(presented)
        return controller
    }
    func updateUIViewController(_ controller: NotebookController, context: Context) {
        controller.setPresented(presented)
        controller.refresh()
    }
    static func dismantleUIViewController(_ controller: NotebookController, coordinator: ()) { controller.flush() }
}

/// UIPageViewController asks for neighbors lazily: hundreds of linked PDF pages
/// do not turn into hundreds of live PencilKit canvases.
@MainActor
final class NotebookController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let session: BookSession
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private var transitioning = false
    private var presented = true

    init(session: BookSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic controller") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(pager)
        view.addSubview(pager.view)
        pager.didMove(toParent: self)
        pager.dataSource = self
        pager.delegate = self
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pager.view.frame = view.bounds
    }

    func setPresented(_ visible: Bool) {
        guard presented != visible else { return }
        if presented, isViewLoaded { flush() }
        presented = visible
        if isViewLoaded { view.isUserInteractionEnabled = visible }
    }

    func refresh() {
        guard isViewLoaded, presented else { return }
        view.isUserInteractionEnabled = true
        configurePagerInput()
        if transitioning { return }
        let page = session.notePage, sheet = session.selectedSheet
        if let current = pager.viewControllers?.first as? NoteSheetController,
           current.pdfPage == page, current.sheet.id == sheet.id {
            current.refresh(sheet: sheet)
            return
        }
        flush()
        let controller = makeController(page: page, sheet: sheet)
        pager.setViewControllers([controller], direction: .forward, animated: false)
        configurePagerInput()
    }

    private func makeController(page: Int, sheet: NoteSheet) -> NoteSheetController {
        let controller = NoteSheetController(session: session, pdfPage: page, sheet: sheet)
        controller.onZoomStateChange = { [weak self] in self?.configurePagerInput() }
        return controller
    }

    private func configurePagerInput() {
        func configure(_ view: UIView) {
            if let scroll = view as? UIScrollView {
                configureFingerNavigation(scroll, app: session.app)
                let zoomed = (pager.viewControllers?.first as? NoteSheetController)?.isZoomed ?? false
                scroll.panGestureRecognizer.isEnabled = !zoomed
            }
            // Configure only the paging scroll, not nested note-sheet views.
            if view is UIScrollView { return }
            for child in view.subviews { configure(child) }
        }
        configure(pager.view)
    }

    func flush() {
        for controller in pager.viewControllers ?? [] { (controller as? NoteSheetController)?.surface.flush() }
    }

    private func neighbor(of controller: UIViewController, delta: Int) -> UIViewController? {
        guard let current = controller as? NoteSheetController, current.pdfPage == session.notePage else { return nil }
        let sheets = session.sheets(on: current.pdfPage)
        guard let index = sheets.firstIndex(where: { $0.id == current.sheet.id }), sheets.indices.contains(index + delta) else { return nil }
        return makeController(page: current.pdfPage, sheet: sheets[index + delta])
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        neighbor(of: viewController, delta: -1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        neighbor(of: viewController, delta: 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        session.activity()
        transitioning = true
        flush()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        transitioning = false
        if completed, let current = pageViewController.viewControllers?.first as? NoteSheetController,
           current.pdfPage == session.notePage {
            session.selectSheet(current.sheet.id, on: current.pdfPage)
        }
        refresh()
    }
}

@MainActor
private final class NoteSheetController: UIViewController, UIScrollViewDelegate {
    // Stable logical paper dimensions, independent of screen/divider/zoom.
    private static let paperSize = CGSize(width: 768, height: 1024)
    let pdfPage: Int
    private(set) var sheet: NoteSheet
    let surface: DrawingSurface
    var onZoomStateChange: (() -> Void)?
    var isZoomed: Bool { fitScale > 0 && scroll.zoomScale > fitScale * 1.02 }
    private var previouslyZoomed = false
    private let session: BookSession
    private let scroll = UIScrollView()
    private let paper = PaperView(frame: CGRect(origin: .zero, size: NoteSheetController.paperSize))
    private var fitScale: CGFloat = 0
    private var previousSize: CGSize = .zero
    private var fitting = false

    init(session: BookSession, pdfPage: Int, sheet: NoteSheet) {
        self.session = session
        self.pdfPage = pdfPage
        self.sheet = sheet
        surface = DrawingSurface(session: session, target: .note(page: pdfPage, sheet: sheet.id))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic controller") }

    override func loadView() {
        view = scroll
        scroll.backgroundColor = Theme.backgroundUI
        scroll.delegate = self
        scroll.bouncesZoom = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        paper.paper = sheet.paper
        paper.layer.borderWidth = 0.5
        paper.layer.borderColor = Theme.gridUI.cgColor
        scroll.addSubview(paper)
        surface.frame = paper.bounds
        paper.addSubview(surface)
        scroll.contentSize = Self.paperSize
        refresh(sheet: sheet)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scroll.bounds.width > 24, scroll.bounds.height > 24 else { return }
        guard previousSize != scroll.bounds.size else { centerPaper(); return }
        previousSize = scroll.bounds.size
        let ratio = fitScale > 0 ? scroll.zoomScale / fitScale : 1
        fitScale = min((scroll.bounds.width - 24) / Self.paperSize.width, (scroll.bounds.height - 24) / Self.paperSize.height)
        fitting = true
        scroll.maximumZoomScale = fitScale * 6
        scroll.minimumZoomScale = fitScale
        scroll.setZoomScale(min(scroll.maximumZoomScale, max(fitScale, fitScale * ratio)), animated: false)
        fitting = false
        centerPaper()
        refresh(sheet: sheet)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        surface.flush()
    }

    func refresh(sheet: NoteSheet) {
        self.sheet = sheet
        guard isViewLoaded else { return }
        paper.paper = sheet.paper
        surface.applySettings()
        configureFingerNavigation(scroll, app: session.app)
        // At fit, horizontal finger swipes go to the notebook pager. Once zoomed
        // in, fingers pan the sheet; header arrows remain available for paging.
        scroll.panGestureRecognizer.isEnabled = isZoomed
        if previouslyZoomed != isZoomed {
            previouslyZoomed = isZoomed
            onZoomStateChange?()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { paper }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { session.activity() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating { session.activity() }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !fitting else { return }
        if scrollView.isZooming { session.activity() }
        centerPaper()
        refresh(sheet: sheet)
    }

    private func centerPaper() {
        let horizontal = max(0, (scroll.bounds.width - paper.frame.width) / 2)
        let vertical = max(0, (scroll.bounds.height - paper.frame.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if scroll.contentInset != inset { scroll.contentInset = inset }
    }
}
