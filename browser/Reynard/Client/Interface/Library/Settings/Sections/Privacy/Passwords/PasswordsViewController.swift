//
//  PasswordsViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Settings screen that lists every saved login (HTTP authentication and
//  web-form logins) grouped by host. Rows push a detail screen where the
//  password can be revealed, edited or deleted; rows can also be deleted with
//  a trailing swipe, and the whole store can be cleared from the bottom
//  section.
//

import UIKit

final class PasswordsViewController: SettingsTableViewController {
    private enum Section {
        case empty
        case host
        case actions
    }

    private struct HostGroup {
        let host: String
        let records: [LoginRecord]
    }

    private enum ActionRow: CaseIterable {
        case removeAll
    }

    private var groups: [HostGroup] = []

    private var displayedSections: [Section] {
        guard !groups.isEmpty else {
            return [.empty]
        }

        return Array(repeating: .host, count: groups.count) + [.actions]
    }

    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Passwords", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadLogins()
    }

    private func reloadLogins() {
        let records = LoginStore.shared.allLogins()
        var order: [String] = []
        var grouped: [String: [LoginRecord]] = [:]

        for record in records {
            let host = record.host.isEmpty ? LoginStore.normalizedHost(forOrigin: record.origin) : record.host
            let key = host.isEmpty ? record.origin : host
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(record)
        }

        groups = order.map { HostGroup(host: $0, records: grouped[$0] ?? []) }
        tableView.reloadData()
    }

    // MARK: - Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return displayedSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedSections.indices.contains(section) else {
            return 0
        }

        switch displayedSections[section] {
        case .empty:
            return 1
        case .host:
            return group(at: section)?.records.count ?? 0
        case .actions:
            return ActionRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayedSections.indices.contains(indexPath.section) else {
            return UITableViewCell()
        }

        switch displayedSections[indexPath.section] {
        case .empty:
            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = NSLocalizedString("No saved passwords", comment: "")
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            return cell

        case .host:
            guard let record = record(at: indexPath) else {
                return UITableViewCell()
            }

            let cell = SettingsTableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = record.username.isEmpty
                ? NSLocalizedString("(No user name)", comment: "")
                : record.username
            cell.detailTextLabel?.text = detailTitle(for: record)
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell

        case .actions:
            guard ActionRow.allCases.indices.contains(indexPath.row) else {
                return UITableViewCell()
            }

            switch ActionRow.allCases[indexPath.row] {
            case .removeAll:
                let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = NSLocalizedString("Remove All Passwords", comment: "")
                cell.textLabel?.textColor = .systemRed
                cell.textLabel?.textAlignment = .center
                cell.accessoryType = .none
                return cell
            }
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard displayedSections.indices.contains(section), displayedSections[section] == .host else {
            return nil
        }

        return group(at: section)?.host
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard displayedSections.indices.contains(indexPath.section) else {
            return
        }

        switch displayedSections[indexPath.section] {
        case .empty:
            return

        case .host:
            guard let record = record(at: indexPath) else {
                return
            }
            navigationController?.pushViewController(
                PasswordDetailViewController(recordID: record.id),
                animated: true
            )

        case .actions:
            guard ActionRow.allCases.indices.contains(indexPath.row) else {
                return
            }
            switch ActionRow.allCases[indexPath.row] {
            case .removeAll:
                confirmRemoveAll()
            }
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard displayedSections.indices.contains(indexPath.section),
              displayedSections[indexPath.section] == .host,
              let record = record(at: indexPath) else {
            return nil
        }

        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { _, _, completion in
            LoginStore.shared.delete(id: record.id)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: - Helpers

    private func group(at section: Int) -> HostGroup? {
        let hostSections = groups.indices
        guard displayedSections.indices.contains(section),
              displayedSections[section] == .host,
              hostSections.contains(section) else {
            return nil
        }

        return groups[section]
    }

    private func record(at indexPath: IndexPath) -> LoginRecord? {
        guard let group = group(at: indexPath.section),
              group.records.indices.contains(indexPath.row) else {
            return nil
        }

        return group.records[indexPath.row]
    }

    private func detailTitle(for record: LoginRecord) -> String {
        switch record.kind {
        case .http:
            return NSLocalizedString("HTTP Authentication", comment: "")
        case .form:
            return NSLocalizedString("Web Form", comment: "")
        }
    }

    private func confirmRemoveAll() {
        AlertPresenter.show(
            title: nil,
            message: NSLocalizedString("This will remove all saved passwords. This action cannot be undone.", comment: ""),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Remove", comment: "Destructive button"), style: .destructive) {
                    LoginStore.shared.removeAll()
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
}

final class PasswordDetailViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case credentials
        case actions
    }

    private enum CredentialRow: CaseIterable {
        case website
        case username
        case password
    }

    private enum ActionRow: CaseIterable {
        case edit
        case delete
    }

    private let recordID: Int64
    private var record: LoginRecord?
    private var isPasswordRevealed = false

    init(recordID: Int64) {
        self.recordID = recordID
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Password", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRecord()
    }

    private func reloadRecord() {
        record = LoginStore.shared.allLogins().first { $0.id == recordID }
        if record == nil, isViewLoaded, navigationController?.topViewController === self {
            navigationController?.popViewController(animated: true)
            return
        }

        title = record?.username.isEmpty == false
            ? record?.username
            : NSLocalizedString("Password", comment: "")
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section.allCases[safe: section] {
        case .some(.credentials):
            return CredentialRow.allCases.count
        case .some(.actions):
            return ActionRow.allCases.count
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section.allCases[safe: indexPath.section] else {
            return UITableViewCell()
        }

        switch section {
        case .credentials:
            guard let row = CredentialRow.allCases[safe: indexPath.row], let record else {
                return UITableViewCell()
            }

            let cell = SettingsTableViewCell(style: .value1, reuseIdentifier: nil)
            cell.detailTextLabel?.textColor = .secondaryLabel

            switch row {
            case .website:
                cell.textLabel?.text = NSLocalizedString("Website", comment: "")
                cell.detailTextLabel?.text = record.host.isEmpty ? record.origin : record.host
                cell.selectionStyle = .none
            case .username:
                cell.textLabel?.text = NSLocalizedString("User Name", comment: "")
                cell.detailTextLabel?.text = record.username.isEmpty
                    ? NSLocalizedString("(No user name)", comment: "")
                    : record.username
                cell.selectionStyle = .none
            case .password:
                cell.textLabel?.text = NSLocalizedString("Password", comment: "")
                cell.detailTextLabel?.text = isPasswordRevealed
                    ? record.password
                    : String(repeating: "•", count: max(6, min(record.password.count, 12)))
                cell.accessoryType = .none
                configureRevealGesture(on: cell)
            }

            return cell

        case .actions:
            guard let row = ActionRow.allCases[safe: indexPath.row] else {
                return UITableViewCell()
            }

            let cell = SettingsTableViewCell(style: .default, reuseIdentifier: nil)
            switch row {
            case .edit:
                cell.textLabel?.text = NSLocalizedString("Edit", comment: "")
                cell.textLabel?.textColor = view.tintColor
            case .delete:
                cell.textLabel?.text = NSLocalizedString("Delete Password", comment: "")
                cell.textLabel?.textColor = .systemRed
            }
            cell.accessoryType = .none
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard Section.allCases[safe: section] == .credentials else {
            return nil
        }

        switch record?.kind {
        case .some(.http):
            return NSLocalizedString("HTTP Authentication", comment: "")
        case .some(.form):
            return NSLocalizedString("Web Form", comment: "")
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let section = Section.allCases[safe: indexPath.section] else {
            return
        }

        switch section {
        case .credentials:
            guard CredentialRow.allCases[safe: indexPath.row] == .password else {
                return
            }
            isPasswordRevealed.toggle()
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)

        case .actions:
            guard let row = ActionRow.allCases[safe: indexPath.row] else {
                return
            }
            switch row {
            case .edit:
                presentEditAlert()
            case .delete:
                confirmDelete()
            }
        }
    }

    private func configureRevealGesture(on cell: SettingsTableViewCell) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(revealPasswordTapped))
        cell.detailTextLabel?.isUserInteractionEnabled = true
        cell.detailTextLabel?.addGestureRecognizer(tap)
        cell.configureDetailTextCopying()
    }

    @objc private func revealPasswordTapped() {
        isPasswordRevealed.toggle()
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }

    private func presentEditAlert() {
        guard let record else {
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("Edit Password", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("User Name", comment: "")
            textField.text = record.username
            textField.textContentType = .username
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("Password", comment: "")
            textField.text = record.password
            textField.textContentType = .password
            textField.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { [weak self, weak alert] _ in
            guard let self else {
                return
            }
            let username = alert?.textFields?.first?.text ?? record.username
            let password = alert?.textFields?.last?.text ?? record.password
            _ = LoginStore.shared.update(
                id: record.id,
                origin: record.origin,
                formActionOrigin: record.formActionOrigin,
                httpRealm: record.httpRealm,
                kind: record.kind,
                username: username,
                password: password
            )
        })
        present(alert, animated: true)
    }

    private func confirmDelete() {
        guard let record else {
            return
        }

        AlertPresenter.show(
            title: nil,
            message: NSLocalizedString("This will delete the saved password. This action cannot be undone.", comment: ""),
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Delete", comment: "Destructive button"), style: .destructive) { [weak self] in
                    LoginStore.shared.delete(id: record.id)
                    self?.navigationController?.popViewController(animated: true)
                },
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: "")),
            ]
        )
    }
}
