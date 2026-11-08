//
//  LoginAutofillBar.swift
//  Reynard
//

import UIKit

/// Floating strip that offers the logins this app stored for the focused page.
///
/// Gecko's built-in autofill route surfaces the iOS password list, which only
/// knows credentials saved in Apple's Passwords app for an associated domain --
/// it can never see `LoginStore`. This bar closes that gap: it appears when a
/// login field inside web content takes focus and fills the form through
/// `GeckoSession.autofillLogin(username:password:)`.
final class LoginAutofillBar: UIView {
    private let stack = UIStackView()
    private let iconView = UIImageView(image: UIImage(named: "reynard.key") ?? UIImage(systemName: "key.fill"))
    private let closeButton = UIButton(type: .system)

    var onSelect: ((LoginRecord) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth]
        backgroundColor = EdgeChromePalette.surface
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func configureHierarchy() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "reynard.xmark") ?? UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)

        addSubview(iconView)
        addSubview(stack)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            stack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func configure(with logins: [LoginRecord]) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for login in logins.prefix(3) {
            let button = UIButton(type: .system)
            button.setTitle(login.username.isEmpty ? login.host : login.username, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.titleLabel?.lineBreakMode = .byTruncatingMiddle
            button.setTitleColor(.label, for: .normal)
            button.backgroundColor = EdgeChromePalette.field
            button.layer.cornerRadius = 10
            button.layer.cornerCurve = .continuous
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            button.addAction(
                UIAction { [weak self] _ in self?.onSelect?(login) },
                for: .touchUpInside
            )
            stack.addArrangedSubview(button)
        }
    }

    @objc private func handleClose() {
        onClose?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.18
    }
}

/// Owns the bar's lifecycle: listens to Gecko's field-focus notifications and
/// positions the bar above the keyboard inside the browser window.
final class LoginAutofillPresenter {
    static let shared = LoginAutofillPresenter()

    private weak var bar: LoginAutofillBar?
    private weak var window: UIWindow?
    private weak var activeSession: GeckoSession?
    private var keyboardTop: CGFloat?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFocusChange(_:)),
            name: GeckoAutofillHandler.focusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func handleFocusChange(_ notification: Notification) {
        guard let session = notification.object as? GeckoSession else {
            return
        }

        let origin = notification.userInfo?["origin"] as? String ?? ""
        let accepts = notification.userInfo?["accepts"] as? Bool ?? false
        guard accepts, !origin.isEmpty else {
            hide()
            return
        }

        let logins = LoginStore.shared.logins(forOrigin: origin)
        guard !logins.isEmpty else {
            hide()
            return
        }

        activeSession = session
        window = session.engineView?.window
        present(with: logins)
    }

    private func present(with logins: [LoginRecord]) {
        guard let window else {
            return
        }

        let bar = self.bar ?? LoginAutofillBar(frame: .zero)
        self.bar = bar
        bar.onSelect = { [weak self] login in
            self?.activeSession?.autofillLogin(username: login.username, password: login.password)
            self?.hide()
        }
        bar.onClose = { [weak self] in
            self?.hide()
        }
        bar.configure(with: logins)

        if bar.superview !== window {
            window.addSubview(bar)
        }
        layoutBar()
        bar.isHidden = false
    }

    private func layoutBar() {
        guard let bar, let window else {
            return
        }

        let height: CGFloat = 44
        let horizontalInset: CGFloat = 12
        let bottom: CGFloat
        if let keyboardTop, keyboardTop < window.bounds.height {
            bottom = keyboardTop - 8
        } else {
            bottom = window.bounds.height
                - window.safeAreaInsets.bottom
                - 60
        }
        bar.frame = CGRect(
            x: horizontalInset,
            y: bottom - height,
            width: window.bounds.width - horizontalInset * 2,
            height: height
        )
    }

    @objc private func handleKeyboardChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window else {
            return
        }
        keyboardTop = window.convert(frame, from: window.screen.coordinateSpace).minY
        layoutBar()
    }

    @objc private func handleKeyboardHide(_ notification: Notification) {
        keyboardTop = nil
        layoutBar()
    }

    private func hide() {
        bar?.removeFromSuperview()
        bar = nil
        activeSession = nil
    }
}
