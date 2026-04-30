import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let zoomScale: CGFloat
    let documentRevision: UInt64
    /// When set to a non-nil string matching an HTML element `id`, the web
    /// view smoothly scrolls that element into view, then the binding is reset
    /// to `nil` so the same heading can be tapped again later.
    @Binding var scrollAnchor: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true   // required for KaTeX
        cfg.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = zoomScale
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastDocumentRevision = documentRevision
        context.coordinator.lastZoomScale = zoomScale
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // ── Document change ──────────────────────────────────────────────────
        if context.coordinator.lastDocumentRevision != documentRevision {
            webView.loadHTMLString(html, baseURL: nil)
            context.coordinator.lastDocumentRevision = documentRevision
            // Clear any pending anchor so it doesn't fire on the old page.
            context.coordinator.pendingAnchor = nil
        }

        // ── Zoom change ──────────────────────────────────────────────────────
        if context.coordinator.lastZoomScale != zoomScale {
            webView.pageZoom = zoomScale
            context.coordinator.lastZoomScale = zoomScale
        }

        // ── TOC scroll jump ──────────────────────────────────────────────────
        if let anchor = scrollAnchor {
            // Guard against re-firing the same anchor (SwiftUI may call
            // updateNSView multiple times before the async nil-reset runs).
            guard anchor != context.coordinator.pendingAnchor else { return }
            context.coordinator.pendingAnchor = anchor

            // Validate: anchors are always "h-<digits>" — never user content.
            let safe = anchor.filter { $0.isLetter || $0.isNumber || $0 == "-" }
            if !safe.isEmpty {
                webView.evaluateJavaScript(
                    "var e=document.getElementById('\(safe)');if(e)e.scrollIntoView({behavior:'smooth'});"
                ) { _, _ in }
            }
            // Reset binding so the same heading can be tapped again later.
            DispatchQueue.main.async { self.scrollAnchor = nil }
        } else {
            context.coordinator.pendingAnchor = nil
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        // Release the current page's DOM / JS heap.
        webView.loadHTMLString("", baseURL: nil)
        coordinator.lastDocumentRevision = nil
    }

    // -------------------------------------------------------------------------

    final class Coordinator {
        var lastDocumentRevision: UInt64?
        var lastZoomScale: CGFloat = 1.0
        var pendingAnchor: String? = nil
    }
}
