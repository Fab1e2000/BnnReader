import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    static let bnnReaderRequestOpen = Notification.Name("bnnReaderRequestOpen")
    /// Object: `Double` delta to add, or `nil` to reset to 100 %.
    static let bnnReaderRequestZoom = Notification.Name("bnnReaderRequestZoom")
}

// MARK: - Zoom constants

enum ZoomConstants {
    static let minScale:     CGFloat = 0.7
    static let maxScale:     CGFloat = 2.2
    static let step:         CGFloat = 0.1
    static let defaultScale: CGFloat = 1.0
    static func clamp(_ v: CGFloat) -> CGFloat { min(max(v, minScale), maxScale) }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var viewModel        = ReaderViewModel()
    @State private var isImporting      = false
    @State private var zoomScale:       CGFloat  = ZoomConstants.defaultScale
    @State private var gestureBaseZoom: CGFloat  = ZoomConstants.defaultScale
    @State private var showTOC          = false
    @State private var tocScrollAnchor: String?  = nil

    var body: some View {
        NavigationStack {
            Group { readerContent }
                .frame(minWidth: 480, minHeight: 440)
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { showTOC.toggle() } label: {
                            Image(systemName: "list.bullet.indent")
                        }
                        .help("目录")
                        .disabled(viewModel.contentMode != .html || viewModel.toc.isEmpty)
                        .popover(isPresented: $showTOC, arrowEdge: .bottom) {
                            TOCView(entries: viewModel.toc) { entry in
                                tocScrollAnchor = "h-\(entry.id)"
                                showTOC = false
                            }
                        }

                        Button { isImporting = true } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .help("打开 Markdown / PDF 文件  ⌘O")
                    }
                }
        }
        .onChange(of: zoomScale) { _, v in gestureBaseZoom = v }
        .onChange(of: viewModel.documentRevision) { _, _ in showTOC = false }
        .onAppear {
            if let url = AppDelegate.consumePendingOpenURLs().first { viewModel.open(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bnnReaderDidReceiveOpenURLs)) { note in
            guard !viewModel.hasLoadedDocument else { return }
            if let url = AppDelegate.consumePendingOpenURLs().first { viewModel.open(url: url); return }
            if let urls = note.object as? [URL], let first = urls.first { viewModel.open(url: first) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bnnReaderRequestOpen)) { _ in
            isImporting = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .bnnReaderRequestZoom)) { note in
            switch note.object {
            case let d as Double: zoomScale = ZoomConstants.clamp(zoomScale + CGFloat(d))
            default:              zoomScale = ZoomConstants.defaultScale
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: viewModel.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls): if let url = urls.first { viewModel.open(url: url) }
            case .failure(let err):  viewModel.reportOpenFailure(err)
            }
        }
    }

    // MARK: Content area

    @ViewBuilder
    private var readerContent: some View {
        if viewModel.isLoadingDocument {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("正在加载文档…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if !viewModel.hasLoadedDocument {
            ContentUnavailableView {
                Label("Banana Reader", systemImage: "book.closed")
            } description: {
                Text("打开 Markdown 或 PDF 文件，以只读视图进行阅读。")
            } actions: {
                Button("打开文件…") { isImporting = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else {
            switch viewModel.contentMode {
            case .html:
                ReaderCardView(
                    zoomScale:        zoomScale,
                    documentRevision: viewModel.documentRevision,
                    html:             viewModel.renderedHTML,
                    onMagnifyChanged: { v in zoomScale = ZoomConstants.clamp(gestureBaseZoom * v) },
                    onMagnifyEnded:   { gestureBaseZoom = zoomScale },
                    scrollAnchor:     $tocScrollAnchor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { toolbarFade }

            case .pdf:
                if let doc = viewModel.openedPDFDocument {
                    PDFReaderView(document: doc, zoomScale: zoomScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .top) { toolbarFade }
                } else {
                    ContentUnavailableView(
                        "无法显示 PDF",
                        systemImage: "exclamationmark.triangle",
                        description: Text("请重新打开文件。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// Mimics the macOS 26 scroll-edge fade that SwiftUI's own ScrollView gets
    /// automatically.  NSViewRepresentable content (WKWebView / PDFView) is
    /// opaque to the system, so we add the gradient manually.
    private var toolbarFade: some View {
        LinearGradient(
            stops: [
                .init(color: Color(nsColor: .windowBackgroundColor), location: 0),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 28)
        .allowsHitTesting(false)
    }

    private var navigationTitle: String {
        viewModel.hasLoadedDocument ? viewModel.documentName : "Banana Reader"
    }
}
