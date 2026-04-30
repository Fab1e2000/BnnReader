import SwiftUI

struct ReaderCardView: View {
    let zoomScale: CGFloat
    let documentRevision: UInt64
    let html: String
    let onMagnifyChanged: (CGFloat) -> Void
    let onMagnifyEnded: () -> Void
    @Binding var scrollAnchor: String?

    var body: some View {
        MarkdownWebView(
            html: html,
            zoomScale: zoomScale,
            documentRevision: documentRevision,
            scrollAnchor: $scrollAnchor
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            MagnifyGesture()
                .onChanged { value in onMagnifyChanged(value.magnification) }
                .onEnded   { _     in onMagnifyEnded() }
        )
    }
}
