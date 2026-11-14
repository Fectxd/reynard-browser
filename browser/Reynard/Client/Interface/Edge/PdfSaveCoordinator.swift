//
//  PdfSaveCoordinator.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Saving from Gecko's pdf.js viewer (download button / Ctrl-S) arrives as
//  "GeckoView:SavePdf" with a blob: URL holding the PDF *including* the user's
//  annotations and form edits. The stock handling re-downloaded the original
//  URL, which drops every edit (and fails for files opened via
//  LocalFileServer). Here the blob is read from the page itself and:
//
//    - for a PDF opened from Files: "保存" writes it back over the original
//      file (coordinated write through the kept security-scoped grant);
//    - always: "另存为…" exports it to a location the user picks in Files.
//

import GeckoView
import UIKit

@MainActor
enum PdfSaveCoordinator {
    /// Returns false when the edited PDF could not be read, so the caller can
    /// fall back to the old download behaviour.
    static func handle(session: GeckoSession, request: SavePdfInfo, window: UIWindow?) async -> Bool {
        guard let blobURL = URL(string: request.url),
              let data = try? await session.fetchImageData(from: blobURL),
              !data.isEmpty,
              let presenter = UIApplication.shared.topViewController(for: window) else {
            return false
        }

        let originalURL = request.originalUrl.flatMap(URL.init(string:))
        let localFile = originalURL.flatMap { LocalFileServer.shared.originalFileURL(forServedURL: $0) }
        let fileName = suggestedFileName(request: request, originalURL: originalURL, localFile: localFile)

        let sheet = UIAlertController(title: fileName, message: nil, preferredStyle: .actionSheet)
        if let localFile {
            sheet.addAction(UIAlertAction(title: "保存", style: .default) { _ in
                if writeInPlace(data, to: localFile) {
                    showResult("已保存", in: presenter)
                } else {
                    // The location refused the write (read-only provider…):
                    // offer Save As instead of losing the edits.
                    presentSaveAs(data: data, fileName: fileName, from: presenter, message: "无法写回原文件，请选择保存位置")
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "另存为…", style: .default) { _ in
            presentSaveAs(data: data, fileName: fileName, from: presenter, message: nil)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true)
        return true
    }

    private static func suggestedFileName(request: SavePdfInfo, originalURL: URL?, localFile: URL?) -> String {
        var name = localFile?.lastPathComponent
            ?? request.filename
            ?? originalURL?.lastPathComponent
            ?? "document.pdf"
        name = name.removingPercentEncoding ?? name
        if name.isEmpty || name == "/" {
            name = "document.pdf"
        }
        if URL(fileURLWithPath: name).pathExtension.lowercased() != "pdf" {
            name += ".pdf"
        }
        return name
    }

    private static func writeInPlace(_ data: Data, to fileURL: URL) -> Bool {
        _ = fileURL.startAccessingSecurityScopedResource()
        var coordinationError: NSError?
        var writeSucceeded = false
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { url in
            writeSucceeded = (try? data.write(to: url, options: .atomic)) != nil
        }
        return coordinationError == nil && writeSucceeded
    }

    private static func presentSaveAs(data: Data, fileName: String, from presenter: UIViewController, message: String?) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PdfSaveAs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempURL = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: tempURL, options: .atomic)
        } catch {
            showResult("保存失败", in: presenter)
            return
        }

        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(url: tempURL, in: .exportToService)
        }
        // The temporary copy only lives until the picker is done with it.
        let cleaner = TemporaryFileCleaner(folder: folder) { exported in
            if exported {
                showResult("已保存", in: presenter)
            }
        }
        picker.delegate = cleaner
        objc_setAssociatedObject(picker, &TemporaryFileCleaner.associationKey, cleaner, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let message {
            showResult(message, in: presenter) {
                presenter.present(picker, animated: true)
            }
        } else {
            presenter.present(picker, animated: true)
        }
    }

    private static func showResult(_ text: String, in presenter: UIViewController, then: (() -> Void)? = nil) {
        let alert = UIAlertController(title: text, message: nil, preferredStyle: .alert)
        presenter.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            alert.dismiss(animated: true, completion: then)
        }
    }
}

private final class TemporaryFileCleaner: NSObject, UIDocumentPickerDelegate {
    static var associationKey: UInt8 = 0

    private let folder: URL
    private let completion: (Bool) -> Void

    init(folder: URL, completion: @escaping (Bool) -> Void) {
        self.folder = folder
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        try? FileManager.default.removeItem(at: folder)
        completion(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        try? FileManager.default.removeItem(at: folder)
        completion(false)
    }
}
