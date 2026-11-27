//
//  ClientCertificateImporter.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  "导入客户端证书" (Settings > Privacy): pick a PKCS#12 file (.p12 / .pfx)
//  in Files, enter its password, and import the certificate with its private
//  key into Gecko's certificate database. Sites that ask for a client
//  certificate (e.g. FNMT / university single sign-on) then get a matching
//  one automatically ("security.default_personal_cert" = Select
//  Automatically, see RuntimePreferences).
//

import GeckoView
import UIKit
import UniformTypeIdentifiers

@MainActor
enum ClientCertificateImporter {
    private static var activeCoordinator: PickerCoordinator?

    static func present(from presenter: UIViewController) {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            let types: [UTType] = [
                UTType("com.rsa.pkcs-12"),
                UTType(filenameExtension: "p12"),
                UTType(filenameExtension: "pfx"),
            ].compactMap { $0 }
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: types.isEmpty ? [.data] : types,
                asCopy: true
            )
        } else {
            picker = UIDocumentPickerViewController(
                documentTypes: ["com.rsa.pkcs-12", "public.data"],
                in: .import
            )
        }
        picker.allowsMultipleSelection = false
        let coordinator = PickerCoordinator { [weak presenter] url in
            activeCoordinator = nil
            guard let presenter, let url else {
                return
            }
            askPassword(for: url, from: presenter)
        }
        activeCoordinator = coordinator
        picker.delegate = coordinator
        presenter.present(picker, animated: true)
    }

    private static func askPassword(for fileURL: URL, from presenter: UIViewController) {
        let alert = UIAlertController(
            title: "证书密码",
            message: "输入导出该证书（\(fileURL.lastPathComponent)）时设置的密码。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "密码"
            field.textContentType = .password
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            try? FileManager.default.removeItem(at: fileURL)
        })
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak alert, weak presenter] _ in
            let password = alert?.textFields?.first?.text ?? ""
            Task { @MainActor in
                await importCertificate(at: fileURL, password: password, from: presenter)
            }
        })
        presenter.present(alert, animated: true)
    }

    private static func importCertificate(at fileURL: URL, password: String, from presenter: UIViewController?) async {
        let result: Int
        do {
            result = try await GeckoRuntime.importClientCertificate(path: fileURL.path, password: password)
        } catch {
            result = -1
        }
        // The picker handed us a private copy; it is no longer needed.
        try? FileManager.default.removeItem(at: fileURL)

        let message: String
        switch result {
        case 0:
            message = "证书已导入。需要证书登录的网站会自动使用它；如果网页已经打开，请刷新一下。"
        case 6:
            message = "密码不正确，请重新导入。"
        case 7:
            message = "无法读取这个文件，请确认它是 .p12 或 .pfx 格式的证书（包含私钥）。"
        case 5, 8:
            message = "这个证书已经导入过了。"
        default:
            message = "导入失败（错误代码 \(result)）。"
        }
        guard let presenter else {
            return
        }
        let alert = UIAlertController(title: result == 0 ? "导入成功" : "无法导入证书", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        presenter.present(alert, animated: true)
    }

    private final class PickerCoordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (URL?) -> Void

        init(completion: @escaping (URL?) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
}
