//
//  CertificateManagerViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  "证书管理器" (Settings > Privacy): lists the client certificates imported
//  into Gecko's certificate database, lets the user delete them (swipe, or tap
//  a certificate), and imports new ones (.p12 / .pfx). Sites asking for a
//  client certificate get a matching one automatically.
//

import GeckoView
import UIKit

final class CertificateManagerViewController: SettingsTableViewController {
    private struct Certificate {
        let dbKey: String
        let name: String
        let issuer: String
        let organization: String
        let notAfter: Date?
    }

    private enum Section: Int, CaseIterable {
        case certificates
        case actions
    }

    private var certificates: [Certificate] = []
    private var isLoading = true

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init() {
        super.init(style: .insetGrouped)
        title = "证书管理器"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadCertificates()
    }

    private func reloadCertificates() {
        Task { @MainActor [weak self] in
            let entries = (try? await GeckoRuntime.listClientCertificates()) ?? []
            guard let self else {
                return
            }
            self.certificates = entries.compactMap { entry in
                guard let dbKey = entry["dbKey"] as? String else {
                    return nil
                }
                let notAfter = (entry["notAfter"] as? NSNumber).map {
                    Date(timeIntervalSince1970: $0.doubleValue / 1000)
                }
                let name = (entry["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "未命名证书"
                return Certificate(
                    dbKey: dbKey,
                    name: name,
                    issuer: entry["issuer"] as? String ?? "",
                    organization: entry["organization"] as? String ?? "",
                    notAfter: notAfter
                )
            }
            self.isLoading = false
            self.tableView.reloadData()
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .certificates:
            return max(certificates.count, 1)
        case .actions:
            return 1
        case .none:
            return 0
        }
    }

    override func sectionText(for section: Int) -> SettingsSectionText {
        switch Section(rawValue: section) {
        case .certificates:
            return SettingsSectionText(
                headerTitle: "你的证书",
                footerTitle: "网站要求证书登录时，会自动使用与之匹配的证书。删除证书会同时删除它的私钥。"
            )
        case .actions:
            return SettingsSectionText(footerTitle: "支持 .p12 / .pfx 格式（需包含私钥），导入时需要输入导出证书时设置的密码。")
        case .none:
            return SettingsSectionText()
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .certificates:
            guard certificates.indices.contains(indexPath.row) else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = isLoading ? "正在读取…" : "还没有导入证书"
                cell.textLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .none
                return cell
            }
            let certificate = certificates[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = certificate.name
            cell.textLabel?.numberOfLines = 2
            var details: [String] = []
            if !certificate.issuer.isEmpty {
                details.append("颁发者：\(certificate.issuer)")
            }
            if let notAfter = certificate.notAfter {
                let expired = notAfter < Date()
                details.append((expired ? "已过期：" : "有效期至：") + Self.dateFormatter.string(from: notAfter))
            }
            cell.detailTextLabel?.text = details.joined(separator: "\n")
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = UIImage(systemName: "person.text.rectangle")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        case .actions:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "导入证书…"
            cell.textLabel?.textColor = view.tintColor
            return cell
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .certificates:
            guard certificates.indices.contains(indexPath.row) else {
                return
            }
            confirmDelete(certificates[indexPath.row], sourceView: tableView.cellForRow(at: indexPath))
        case .actions:
            ClientCertificateImporter.present(from: self) { [weak self] in
                self?.reloadCertificates()
            }
        case .none:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .certificates,
              certificates.indices.contains(indexPath.row) else {
            return nil
        }
        let certificate = certificates[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { [weak self] _, _, completion in
            completion(true)
            self?.delete(certificate)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: - Delete

    private func confirmDelete(_ certificate: Certificate, sourceView: UIView?) {
        let sheet = UIAlertController(
            title: certificate.name,
            message: "删除后，需要这个证书登录的网站将无法登录，除非重新导入。",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "删除证书", style: .destructive) { [weak self] _ in
            self?.delete(certificate)
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(sheet, animated: true)
    }

    private func delete(_ certificate: Certificate) {
        // Remove the row right away; the list is re-read afterwards.
        certificates.removeAll { $0.dbKey == certificate.dbKey }
        tableView.reloadData()
        Task { @MainActor [weak self] in
            _ = try? await GeckoRuntime.deleteClientCertificate(dbKey: certificate.dbKey)
            self?.reloadCertificates()
        }
    }
}
