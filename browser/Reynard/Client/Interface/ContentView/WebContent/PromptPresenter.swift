//
//  PromptPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

@MainActor
final class PromptPresenter: PromptPresenting {
    private var selectPickers: [String: SelectPicker] = [:]
    private var colorPickers: [String: ColorPicker] = [:]
    private var dateTimePickers: [String: DateTimePicker] = [:]
    private var filePickers: [String: FilePicker] = [:]
    
    /// The window owning the session currently being prompted, so a remote prompt
    /// coming from a background window's session is presented in that window
    /// instead of over whichever window happens to be frontmost. `PromptPresenter`
    /// is created per window (per `TabManagerImpl`), so this can only ever refer to
    /// this window's own scene.
    private weak var presentationWindow: UIWindow?
    
    // MARK: - Lifecycle
    
    init() {}
    
    func present(_ request: PromptRequest, for session: GeckoSession) async -> PromptResponse? {
        presentationWindow = session.engineView?.window
        switch request {
        case .alert(let request):
            await presentAlert(request: request)
            return nil
            
        case .button(let request):
            return await presentButton(request: request)
            
        case .text(let request):
            return await presentText(request: request)
            
        case .auth(let request):
            return await presentAuth(request: request, session: session)
            
        case .folderUpload(let request):
            return await presentFolderUpload(request: request)
            
        case .color(let request):
            return await presentColorPicker(session: session, request: request)
            
        case .dateTime(let request):
            return await presentDateTimePicker(session: session, request: request)
            
        case .file(let request):
            return await presentFilePicker(session: session, request: request)
            
        case .choice(let request):
            return await presentSelectPicker(session: session, request: request)
            
        case .share(let request):
            return await presentShare(session: session, request: request)
            
        case .loginSave(let request):
            return await presentLoginSave(request: request, session: session)
        }
    }
    
    func update(_ request: PromptRequest) {
        guard case .choice(let request) = request,
              let picker = selectPickers[request.id] else {
            return
        }
        
        picker.updateChoices(request.choices, mode: request.mode)
    }
    
    func dismiss(promptID: String) {
        if dateTimePickers[promptID] != nil {
            // Gecko fires dismiss when native date UI steals focus; the picker owns completion.
            return
        }
        selectPickers.removeValue(forKey: promptID)?.cancelAndDismiss()
        colorPickers.removeValue(forKey: promptID)?.cancelAndDismiss()
        dateTimePickers.removeValue(forKey: promptID)?.cancelAndDismiss()
        filePickers.removeValue(forKey: promptID)?.cancelAndDismiss()
    }
    
    // MARK: - Basic Prompts
    
    private func presentAlert(request: AlertPromptRequest) async {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return
        }
        
        await withCheckedContinuation { continuation in
            let alert = PromptAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume()
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentButton(request: ButtonPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            
            for index in 0..<3 {
                let title = buttonTitle(at: index, request: request)
                guard !title.isEmpty else { continue }
                
                let isCancel = index == 2 &&
                request.buttonTitles.indices.contains(index) &&
                request.buttonTitles[index] == "cancel"
                alert.addAction(UIAlertAction(
                    title: title,
                    style: isCancel ? .cancel : .default
                ) { _ in
                    response = .button(index)
                })
            }
            
            if alert.actions.isEmpty {
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                    response = .button(0)
                })
            }
            
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentText(request: TextPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: request.title.isEmpty ? nil : request.title,
                message: request.message.isEmpty ? nil : request.message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            alert.addTextField { textField in
                textField.text = request.value
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                response = .text(alert.textFields?.first?.text ?? "")
            })
            presenter.present(alert, animated: true)
        }
    }
    
    private func presentAuth(request: AuthPromptRequest, session: GeckoSession) async -> PromptResponse? {
        let host = URL(string: request.uri)?.host
        let title = host.map {
            String(format: NSLocalizedString("Sign in to %@", comment: "Authentication host"), $0)
        } ?? request.title
        let message = request.level == 2
        ? NSLocalizedString("Your login information will be sent securely.", comment: "")
        : NSLocalizedString("Your login information will not be sent securely.", comment: "")
        let passwordOnly = request.mode == "password"
        
        // Saved HTTP-auth credentials for this host. Private browsing neither
        // reads nor writes them, so private-mode credentials are never stored.
        let savedLogins = session.isPrivateMode
        ? []
        : LoginStore.shared.logins(forOrigin: request.uri, kind: .http)
        
        var preselected: LoginRecord?
        if savedLogins.count == 1 {
            preselected = savedLogins.first
        } else if savedLogins.count > 1 {
            // Multi-account origin (e.g. a router's administration page): let
            // the user pick which account to sign in with before prefilling.
            switch await presentAuthAccountPicker(
                logins: savedLogins,
                title: title.isEmpty ? NSLocalizedString("Sign In", comment: "") : title
            ) {
            case .account(let login):
                preselected = login
            case .other:
                preselected = nil
            case .cancelled:
                return nil
            }
        }
        
        guard let credentials = await presentAuthCredentials(
            title: title.isEmpty ? NSLocalizedString("Sign In", comment: "") : title,
            message: message,
            passwordOnly: passwordOnly,
            username: passwordOnly ? request.username : (preselected?.username ?? request.username),
            password: preselected?.password ?? request.password
        ) else {
            return nil
        }
        
        if let preselected, preselected.username == credentials.username {
            LoginStore.shared.markUsed(id: preselected.id)
        }
        
        await offerToSaveHTTPLogin(
            origin: request.uri,
            username: credentials.username,
            password: credentials.password,
            session: session
        )
        
        return .auth(username: credentials.username, password: credentials.password)
    }
    
    /// The native user name / password dialog for HTTP authentication. Returns
    /// `nil` when the user cancels; the dialog behaviour (and the focus
    /// restoration done by `PromptCoordinator` once this returns) is unchanged.
    private func presentAuthCredentials(
        title: String,
        message: String,
        passwordOnly: Bool,
        username: String,
        password: String
    ) async -> (username: String, password: String)? {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            var result: (username: String, password: String)?
            let alert = PromptAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: result)
            }
            
            if !passwordOnly {
                alert.addTextField { textField in
                    textField.placeholder = NSLocalizedString("User Name", comment: "")
                    textField.text = username
                    textField.textContentType = .username
                    textField.autocapitalizationType = .none
                    textField.autocorrectionType = .no
                }
            }
            
            alert.addTextField { textField in
                textField.placeholder = NSLocalizedString("Password", comment: "")
                textField.text = password
                textField.textContentType = .password
                textField.isSecureTextEntry = true
            }
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Sign In", comment: ""), style: .default) { _ in
                let resolvedUsername = passwordOnly ? username : alert.textFields?.first?.text ?? ""
                let resolvedPassword = alert.textFields?.last?.text ?? ""
                result = (username: resolvedUsername, password: resolvedPassword)
            })
            presenter.present(alert, animated: true)
        }
    }
    
    /// Account chooser shown when an origin has more than one saved login.
    private func presentAuthAccountPicker(
        logins: [LoginRecord],
        title: String
    ) async -> AuthAccountChoice {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return .cancelled
        }
        
        return await withCheckedContinuation { continuation in
            var choice: AuthAccountChoice = .cancelled
            let alert = PromptAlertController(
                title: title,
                message: NSLocalizedString("Choose an account to sign in with.", comment: ""),
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: choice)
            }
            
            for (index, login) in logins.enumerated() {
                let accountTitle = login.username.isEmpty
                ? NSLocalizedString("Saved Password", comment: "")
                : login.username
                alert.addAction(UIAlertAction(title: accountTitle, style: .default) { _ in
                    choice = .account(logins[index])
                })
            }
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Other…", comment: ""), style: .default) { _ in
                choice = .other
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            presenter.present(alert, animated: true)
        }
    }
    
    /// Offers to store freshly entered HTTP-auth credentials.
    private func offerToSaveHTTPLogin(
        origin: String,
        username: String,
        password: String,
        session: GeckoSession
    ) async {
        guard shouldOfferToSaveLogin(origin: origin, username: username, password: password, session: session) else {
            return
        }
        
        guard await confirmSaveLogin(
            username: username,
            host: LoginStore.normalizedHost(forOrigin: origin)
        ) else {
            return
        }
        
        LoginStore.shared.save(
            origin: normalizedOrigin(from: origin),
            kind: .http,
            username: username,
            password: password
        )
    }
    
    /// Normalises a request URI to `scheme://host[:port]` so stored origins stay
    /// clean (matching is by host, Settings groups by host).
    private func normalizedOrigin(from rawURI: String) -> String {
        guard let url = URL(string: rawURI),
              let origin = URLUtils.httpOriginString(for: url) else {
            return rawURI
        }
        
        return origin
    }
    
    private func shouldOfferToSaveLogin(
        origin: String,
        username: String,
        password: String,
        session: GeckoSession
    ) -> Bool {
        guard !session.isPrivateMode else {
            return false
        }
        guard !username.isEmpty || !password.isEmpty else {
            return false
        }
        
        let existing = LoginStore.shared.logins(forOrigin: origin, kind: .http)
        if let match = existing.first(where: { $0.username == username }) {
            // Only offer when the stored password actually changed.
            return match.password != password
        }
        return true
    }
    
    /// Yes/no confirmation used by both the HTTP-auth and web-form save flows.
    private func confirmSaveLogin(username: String, host: String) async -> Bool {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return false
        }
        
        let account = username.isEmpty ? host : "\(username) — \(host)"
        return await withCheckedContinuation { continuation in
            var accepted = false
            let alert = PromptAlertController(
                title: NSLocalizedString("Save Password?", comment: ""),
                message: String(format: NSLocalizedString("Save the password for %@?", comment: "Login save host"), account),
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: accepted)
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Not Now", comment: ""), style: .cancel))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { _ in
                accepted = true
            })
            presenter.present(alert, animated: true)
        }
    }
    
    /// Handles Gecko's `Autocomplete:Save:Login` prompt emitted when a page
    /// submits a login form. Private browsing declines (nothing is persisted).
    private func presentLoginSave(
        request: LoginSavePromptRequest,
        session: GeckoSession
    ) async -> PromptResponse? {
        guard !session.isPrivateMode, let login = request.logins.first else {
            return .loginSave(nil)
        }
        
        let host = LoginStore.normalizedHost(forOrigin: login.origin)
        guard await confirmSaveLogin(username: login.username, host: host) else {
            return .loginSave(nil)
        }
        
        LoginStore.shared.save(
            origin: normalizedOrigin(from: login.origin),
            formActionOrigin: login.formActionOrigin,
            httpRealm: login.httpRealm,
            kind: .form,
            username: login.username,
            password: login.password,
            guid: login.guid.isEmpty ? nil : login.guid
        )
        
        return .loginSave(login)
    }
    
    private func presentFolderUpload(request: FolderUploadPromptRequest) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) else {
            return nil
        }
        
        let message = request.directoryName.isEmpty
        ? NSLocalizedString("Are you sure you want to upload all files? Only do this if you trust the site.", comment: "")
        : NSLocalizedString("Are you sure you want to upload all files from \"\(request.directoryName)\"? Only do this if you trust the site.", comment: "")
        
        return await withCheckedContinuation { continuation in
            var response: PromptResponse?
            let alert = PromptAlertController(
                title: NSLocalizedString("Confirm Upload", comment: ""),
                message: message,
                preferredStyle: .alert
            )
            alert.onDismissed = {
                continuation.resume(returning: response)
            }
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                response = .folderUpload(allowed: false)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Upload", comment: ""), style: .default) { _ in
                response = .folderUpload(allowed: true)
            })
            presenter.present(alert, animated: true)
        }
    }
    
    // MARK: - Picker Prompts
    
    private func presentColorPicker(
        session: GeckoSession,
        request: ColorPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = ColorPicker(
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        colorPickers[request.id] = picker
        defer { colorPickers.removeValue(forKey: request.id) }
        
        let result = await picker.present(initialColor: UIColor(hexString: request.value) ?? .black)
        
        return result.map(PromptResponse.color)
    }
    
    private func presentDateTimePicker(
        session: GeckoSession,
        request: DateTimePromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = DateTimePicker(
            inputMode: request.mode,
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        dateTimePickers[request.id] = picker
        defer { dateTimePickers.removeValue(forKey: request.id) }
        
        let result = await picker.present(
            value: request.value,
            min: request.min,
            max: request.max,
            step: request.step
        )
        
        return result.map(PromptResponse.dateTime)
    }
    
    private func presentFilePicker(
        session: GeckoSession,
        request: FilePickerPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = FilePicker(
            promptId: request.id,
            mode: request.mode,
            mimeTypes: request.mimeTypes,
            capture: request.capture,
            anchorRect: anchor.rect,
            geckoView: anchor.view
        )
        filePickers[request.id] = picker
        defer { filePickers.removeValue(forKey: request.id) }
        
        let result = await picker.present()
        
        return result.map(PromptResponse.files)
    }
    
    private func presentSelectPicker(
        session: GeckoSession,
        request: SelectPromptRequest
    ) async -> PromptResponse? {
        guard let anchor = promptAnchor(for: request.anchor, session: session) else {
            return nil
        }
        
        let picker = SelectPicker(
            mode: request.mode,
            choices: request.choices,
            sourceRect: anchor.rect,
            geckoView: anchor.view
        )
        selectPickers[request.id] = picker
        defer { selectPickers.removeValue(forKey: request.id) }
        
        let result = await picker.present()
        
        return result.map(PromptResponse.choices)
    }
    
    private func presentShare(
        session: GeckoSession,
        request: SharePromptRequest
    ) async -> PromptResponse? {
        guard let presenter = UIApplication.shared.topViewController(for: presentationWindow) as? BrowserViewController,
              let sourceView = session.engineView else {
            return nil
        }
        
        let itemSource = WebShareActivityItemSource(
            title: request.title,
            text: request.text,
            url: request.url
        )
        return await withCheckedContinuation { continuation in
            let sourcePoint = CGPoint(
                x: sourceView.bounds.midX,
                y: sourceView.bounds.midY
            )
            presenter.presentShareSheet(
                items: [itemSource],
                sourceView: sourceView,
                sourceRect: CGRect(origin: sourcePoint, size: .zero)
            ) { completed, error in
                let result: SharePromptResult
                if error != nil {
                    result = .failure
                } else if completed {
                    result = .success
                } else {
                    result = .aborted
                }
                continuation.resume(returning: .share(result))
            }
        }
    }
    
    private func promptAnchor(
        for anchor: PromptAnchor,
        session: GeckoSession
    ) -> (view: UIView, rect: CGRect)? {
        guard let rect = anchor.rect,
              let geckoView = session.engineView,
              let window = geckoView.window else {
            return nil
        }
        
        if session.isAddonPopup {
            return (geckoView, rect)
        }
        
        var localRect = rect
        let windowPoint = window.convert(rect.origin, from: nil)
        localRect.origin = geckoView.convert(windowPoint, from: nil)
        return (geckoView, localRect)
    }
    
    // MARK: - Helpers
    
    private func buttonTitle(at index: Int, request: ButtonPromptRequest) -> String {
        let label = request.buttonTitles.indices.contains(index) ? request.buttonTitles[index] : ""
        let customLabel = request.customButtonTitles.indices.contains(index) ? request.customButtonTitles[index] : ""
        
        switch label {
        case "ok":
            return NSLocalizedString("OK", comment: "")
        case "cancel":
            return NSLocalizedString("Cancel", comment: "")
        case "yes":
            return NSLocalizedString("Yes", comment: "")
        case "no":
            return NSLocalizedString("No", comment: "")
        case "custom":
            return customLabel.isEmpty ? NSLocalizedString("OK", comment: "") : customLabel
        default:
            return ""
        }
    }
}

/// Result of the HTTP-auth account chooser.
private enum AuthAccountChoice {
    case account(LoginRecord)
    case other
    case cancelled
}

private final class WebShareActivityItemSource: NSObject, UIActivityItemSource {
    private let item: Any
    private let title: String
    
    init(title: String, text: String, url: String?) {
        self.title = title
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareURL = trimmedURL.flatMap(URL.init(string:))
        
        if !trimmedText.isEmpty, let trimmedURL, !trimmedURL.isEmpty {
            item = "\(trimmedText)\n\(trimmedURL)"
        } else if !trimmedText.isEmpty {
            item = trimmedText
        } else if let shareURL {
            item = shareURL
        } else if let trimmedURL, !trimmedURL.isEmpty {
            item = trimmedURL
        } else {
            item = title
        }
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return item
    }
    
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        return item
    }
    
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        return title
    }
}
