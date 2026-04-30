import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers
import AppKit

@MainActor
@Observable
final class ReaderViewModel {

    private enum LoadedContent: @unchecked Sendable {
        case markdown(String, [TOCEntry])   // (renderedHTML, toc)
        case pdf(PDFDocument)
    }

    private enum ReaderLoadError: LocalizedError {
        case textFileTooLarge(limitMB: Int)
        var errorDescription: String? {
            switch self {
            case .textFileTooLarge(let mb): return "File is too large to render safely (limit: \(mb) MB)."
            }
        }
    }

    enum ContentMode { case html, pdf }

    nonisolated private static let maxTextFileSizeBytes = 8 * 1024 * 1024
    nonisolated private static let maxTextFileSizeMB    = maxTextFileSizeBytes / (1024 * 1024)

    // MARK: - Published state

    private(set) var documentName:      String       = "No file opened"
    private(set) var renderedHTML:      String       = ""
    private(set) var toc:               [TOCEntry]   = []
    private(set) var contentMode:       ContentMode  = .html
    private(set) var openedPDFDocument: PDFDocument? = nil
    private(set) var isLoadingDocument: Bool         = false
    private(set) var statusMessage:     String       = "Ready"
    private(set) var hasLoadedDocument: Bool         = false
    private(set) var documentRevision:  UInt64       = 0

    private var loadToken:  UInt64              = 0
    private var activeLoad: Task<Void, Never>?

    let supportedTypes: [UTType] = [
        .plainText, .pdf,
        UTType(filenameExtension: "md")       ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
    ]

    // MARK: - Public API

    func open(url: URL) {
        loadToken &+= 1
        let token    = loadToken
        let fileName = url.lastPathComponent

        // ── Eagerly release the previous document's memory ──────────────────
        // Clearing these before the async load begins lets ARC/WebKit free
        // the old content immediately rather than waiting for the new load
        // to complete.  This is the primary fix for RSS growth on file switch.
        renderedHTML      = ""
        toc               = []
        openedPDFDocument = nil

        documentName      = fileName
        statusMessage     = "Loading \(fileName)…"
        isLoadingDocument = true

        activeLoad?.cancel()
        activeLoad = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<LoadedContent, Error>
            do {
                result = .success(try Self.loadContent(from: url))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self, self.loadToken == token else { return }
                switch result {
                case .success(let content): self.applyLoadedContent(content, url: url, fileName: fileName)
                case .failure(let error):   self.applyLoadError(error, fileName: fileName)
                }
            }
        }
    }

    func reportOpenFailure(_ error: Error) {
        statusMessage = "Open failed: \(error.localizedDescription)"
    }

    // MARK: - Background loading (nonisolated — runs off the main actor)

    nonisolated private static func loadContent(from url: URL) throws -> LoadedContent {
        if isPDF(url) { return .pdf(try loadPDF(from: url)) }

        let source = try loadString(from: url)
        let baseURL = url.deletingLastPathComponent()
        let html = MarkdownHTMLRenderer.renderDocument(from: source, baseURL: baseURL)
        let toc  = MarkdownDocument.extractTOC(source)
        return .markdown(html, toc)
    }

    // MARK: - Main-actor application

    private func applyLoadedContent(_ content: LoadedContent, url: URL, fileName: String) {
        documentRevision &+= 1
        switch content {
        case .markdown(let html, let newTOC):
            renderedHTML      = html
            toc               = newTOC
            openedPDFDocument = nil
            contentMode       = .html
        case .pdf(let doc):
            renderedHTML      = ""
            toc               = []
            openedPDFDocument = doc
            contentMode       = .pdf
        }
        documentName      = fileName
        statusMessage     = "Loaded \(fileName)"
        hasLoadedDocument = true
        isLoadingDocument = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    private func applyLoadError(_ error: Error, fileName: String) {
        documentRevision &+= 1
        let errSource = "# Failed to load file\n\nThe selected file could not be loaded.\n\n> \(error.localizedDescription)"
        renderedHTML      = MarkdownHTMLRenderer.renderDocument(from: errSource)
        toc               = []
        openedPDFDocument = nil
        contentMode       = .html
        documentName      = fileName
        statusMessage     = "Error: \(error.localizedDescription)"
        hasLoadedDocument = false
        isLoadingDocument = false
    }

    // MARK: - Static IO helpers

    nonisolated private static func loadString(from url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > maxTextFileSizeBytes {
            throw ReaderLoadError.textFileTooLarge(limitMB: maxTextFileSizeMB)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let encodings: [String.Encoding] = [
            .utf8, .utf16,
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .ascii,
        ]
        for enc in encodings { if let s = String(data: data, encoding: enc) { return s } }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    nonisolated private static func loadPDF(from url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        return doc
    }

    nonisolated private static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .pdf)
    }
}
