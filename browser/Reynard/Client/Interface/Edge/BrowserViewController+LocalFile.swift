//
//  BrowserViewController+LocalFile.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  "本地网页/PDF" in the Edge menu: pick an HTML (.html/.htm/.xhtml) or PDF file
//  from Files and open it in a new tab. PDFs are rendered by Gecko's built-in
//  pdf.js viewer (the same one that already serves web PDFs; its download
//  button goes through TabManager.onSavePdf).
//
//  The picked file is copied into the app's own caches folder first, because
//  a security-scoped Files URL is only readable while the picker grant is held
//  and Gecko loads the page asynchronously.
//

import ObjectiveC
import UIKit
import UniformTypeIdentifiers

extension BrowserViewController {
    func presentLocalFilePicker() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            var types: [UTType] = [.html, .pdf]
            if let xhtml = UTType("public.xhtml") {
                types.append(xhtml)
            }
            if let webArchive = UTType("com.apple.webarchive") {
                types.append(webArchive)
            }
            picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.html", "com.adobe.pdf"], in: .import)
        }
        picker.allowsMultipleSelection = false

        let coordinator = LocalFilePickerCoordinator { [weak self] url in
            self?.openLocalFile(url)
        }
        picker.delegate = coordinator
        objc_setAssociatedObject(picker, &LocalFilePickerCoordinator.associationKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        present(picker, animated: true)
    }

    private func openLocalFile(_ pickedURL: URL) {
        guard let localURL = LocalFilePickerCoordinator.copyIntoSandbox(pickedURL) else {
            return
        }
        _ = tabManager.createRegularTab(
            selecting: true,
            target: .end,
            url: localURL.absoluteString,
            loadImmediately: true
        )
    }
}

private final class LocalFilePickerCoordinator: NSObject, UIDocumentPickerDelegate {
    static var associationKey: UInt8 = 0

    private let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        onPick(url)
    }

    /// Copies the picked file to Caches/LocalFiles/<uuid>/<name> and returns it.
    static func copyIntoSandbox(_ url: URL) -> URL? {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = caches
            .appendingPathComponent("LocalFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
