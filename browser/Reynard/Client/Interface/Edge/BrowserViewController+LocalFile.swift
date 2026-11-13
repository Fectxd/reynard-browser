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
//  The file is opened in place (no copy, so the app does not grow) and served
//  to Gecko by LocalFileServer over 127.0.0.1, because Gecko's content
//  processes cannot read files outside their sandbox.
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
            picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.html", "com.adobe.pdf"], in: .open)
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
        LocalFileServer.shared.publish(pickedURL) { [weak self] servedURL in
            guard let self, let servedURL else {
                return
            }
            _ = self.tabManager.createRegularTab(
                selecting: true,
                target: .end,
                url: servedURL.absoluteString,
                loadImmediately: true
            )
        }
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
}
