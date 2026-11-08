import CoreGraphics
import Foundation

// Twin of windows/LazyScan.App/AppViewModel.LazyPrint.cs: Print with Lazy Print for what is not saved yet,
// the queue and the ID card review. The pages are written as a PDF in a folder of the temp directory and
// that file is opened in Lazy Print, which keeps the path and reads the file again when it prints, so it is
// not tied to the app; a day later the next hand-off deletes it. The iPhone's Lazy Print cannot read that
// folder: the file is copied into the app group they share (`IOSFileActions.openInLazyPrint`) and the
// temp file is deleted at once.

extension AppState {
    /// There are pages the queue would save, nothing else is running and Lazy Print is installed.
    public var canPrintQueueWithLazyPrint: Bool {
        !isBusy && SavePlan.make(scannedPages, options: settings.document).pageCount > 0 && lazyPrintInstalled
    }

    /// Opens the pages the queue would save (the ones left out stay out) as one PDF in Lazy Print. The
    /// queue is left as it is.
    public func printQueueWithLazyPrint() {
        guard !scannedPages.isEmpty else { return }
        let s: ScanSettings = settings
        runExclusive { flag in
            await self.pageEditChain?.value
            let queued: [ScannedPage] = self.scannedPages
            guard !queued.isEmpty else { return }
            let plan: SavePlan = SavePlan.make(queued, options: s.document)
            guard !plan.isEmpty else {
                self.errorMessage = PageFilter.nothingToSaveMessage
                self.errorTitle = PageFilter.nothingSavedTitle
                self.statusMessage = L10n.t("{0}.", DocumentSplitter.queueSummary(queued, options: s.document))
                return
            }
            var collected: [ScannedPage] = []
            for document in plan.documents {
                collected.append(contentsOf: document.pages)
            }
            let pages: [ScannedPage] = collected
            let url: URL = try self.handoffURL(named: L10n.t("Scan|noun"))
            try await Task.detached(priority: .userInitiated) {
                try AppState.writePDFAtomically(pages: pages, pdfSize: s.output.pdfSize, to: url, textLayer: nil,
                                                shouldContinue: { !flag.isCancelled }, progress: nil)
            }.value
            self.openInLazyPrint(url)
        }
    }

    /// Opens the ID card's page, both sides at real size on the paper chosen, as a PDF in Lazy Print.
    public func printIdCardWithLazyPrint() {
        guard let front = idCardFront else { return }
        let back = idCardBack
        let s: ScanSettings = settings
        guard let paperInches = PaperSizes.inches(idCardPaperSize) else { return }
        let pageDPI = IdCardComposer.pageDPI(front.dpi)
        let pageMode = IdCardComposer.pageColorMode(front: front.colorMode, back: back?.colorMode)
        runExclusive { flag in
            let composed: CGImage? = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let f = AppState.idCardSide(of: front) else { return nil }
                let b = back.flatMap { AppState.idCardSide(of: $0) }
                return IdCardComposer.compose(front: f, back: b, dpi: pageDPI, paperInches: paperInches).makeCGImage()
            }.value
            guard let composed else { throw ScanError.exportFailed(L10n.t("The page could not be drawn.")) }
            if flag.isCancelled { throw ScanError.cancelled }
            let url: URL = try self.handoffURL(named: L10n.t("ID card"))
            let page: ScannedPage = ScannedPage(image: composed, dpi: pageDPI, colorMode: pageMode)
            try await Task.detached(priority: .userInitiated) {
                try AppState.writePDFAtomically(pages: [page], pdfSize: s.output.pdfSize, to: url, textLayer: nil,
                                                shouldContinue: { !flag.isCancelled }, progress: nil)
            }.value
            self.openInLazyPrint(url)
        }
    }

    private func handoffURL(named name: String) throws -> URL {
        let manager: FileManager = FileManager.default
        let folder: URL = manager.temporaryDirectory.appendingPathComponent("LazyScan-print", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let cutoff: Date = Date().addingTimeInterval(-86400)
        let old: [URL] = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in old {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < cutoff {
                try? manager.removeItem(at: url)
            }
        }
        return NamingTemplate.uniqueURL(in: folder, base: name, fileExtension: "pdf")
    }

    private func openInLazyPrint(_ url: URL) {
        guard SaveActions.canPrintWithLazyPrint([url]) else {
            errorMessage = L10n.t("Lazy Print can't open this file.")
            return
        }
        runFileAction(.lazyPrint, urls: [url])
        #if os(iOS)
        try? FileManager.default.removeItem(at: url)
        #endif
    }
}
