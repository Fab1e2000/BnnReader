import PDFKit
import SwiftUI

struct PDFReaderView: NSViewRepresentable {
    let document: PDFDocument
    let zoomScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .white

        updateDocumentAndScale(on: pdfView, context: context)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        updateDocumentAndScale(on: pdfView, context: context)
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        pdfView.document = nil
        pdfView.delegate = nil
        coordinator.lastDocumentID = nil
        coordinator.baseScaleFactor = nil
    }

    private func updateDocumentAndScale(on pdfView: PDFView, context: Context) {
        let docID = ObjectIdentifier(document)
        if context.coordinator.lastDocumentID != docID {
            pdfView.document = document
            context.coordinator.lastDocumentID = docID
            context.coordinator.baseScaleFactor = nil
        }

        if context.coordinator.lastZoomScale != zoomScale {
            applyZoom(zoomScale, to: pdfView, context: context)
            context.coordinator.lastZoomScale = zoomScale
        }
    }

    private func applyZoom(_ zoomScale: CGFloat, to pdfView: PDFView, context: Context) {
        if context.coordinator.baseScaleFactor == nil {
            pdfView.autoScales = true
            let base = max(pdfView.scaleFactorForSizeToFit, 0.1)
            context.coordinator.baseScaleFactor = base
        }

        guard let base = context.coordinator.baseScaleFactor else {
            return
        }

        let minScale = base * ZoomConstants.minScale
        let maxScale = base * ZoomConstants.maxScale
        pdfView.minScaleFactor = minScale
        pdfView.maxScaleFactor = maxScale
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(base * zoomScale, minScale), maxScale)
    }

    final class Coordinator {
        var lastDocumentID: ObjectIdentifier?
        var lastZoomScale: CGFloat = 1.0
        var baseScaleFactor: CGFloat?
    }
}
