//
//  EdgeQRCodeShareViewController.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Edge-style "share a QR code" (二维码分享) screen. It shows the current page
//  URL as a QR code (CoreImage CIQRCodeGenerator) and lets the user paste their
//  own text, regenerating the QR for that text — matching Firefox Android's QR
//  share / generate flow.
//

import CoreImage
import UIKit

final class EdgeQRCodeShareViewController: UIViewController {

    private enum UX {
        static let horizontalInset: CGFloat = 20
        static let verticalInset: CGFloat = 16
        static let qrSize: CGFloat = 232
        static let qrScale: CGFloat = 12
        static let titleFontSize: CGFloat = 18
        static let textFieldFontSize: CGFloat = 15
        static let buttonFontSize: CGFloat = 16
        static let blueTint = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    }

    /// The initial value to encode (the current page URL).
    private var encodedText: String

    private let qrImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .white
        view.layer.cornerRadius = 10
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let textField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: UX.textFieldFontSize)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.backgroundColor = UIColor.secondarySystemBackground
        field.layer.cornerRadius = 10
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        field.leftViewMode = .always
        return field
    }()

    private let shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("分享", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: UX.buttonFontSize, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UX.blueTint
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        return button
    }()

    init(initialText: String) {
        self.encodedText = initialText.isEmpty ? "https://example.com" : initialText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "二维码分享"

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "扫描二维码，分享此内容"
        titleLabel.font = .systemFont(ofSize: UX.titleFontSize, weight: .semibold)
        titleLabel.textColor = .label

        let hintLabel = UILabel()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "或粘贴你自己的文本，生成二维码分享。"
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabel

        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        [titleLabel, hintLabel, qrImageView, textField, shareButton].forEach {
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: UX.verticalInset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),

            qrImageView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: UX.verticalInset),
            qrImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: UX.qrSize),
            qrImageView.heightAnchor.constraint(equalToConstant: UX.qrSize),

            textField.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: UX.verticalInset),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            textField.heightAnchor.constraint(equalToConstant: 44),

            shareButton.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: UX.verticalInset),
            shareButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UX.horizontalInset),
            shareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UX.horizontalInset),
            shareButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        textField.text = encodedText
        refreshQRCode()
    }

    // MARK: - QR generation

    private func refreshQRCode() {
        guard let image = EdgeQRCodeShareViewController.makeQRCode(from: encodedText) else {
            qrImageView.image = nil
            return
        }
        qrImageView.image = image
    }

    static func makeQRCode(from string: String, scale: CGFloat = UX.qrScale) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            return nil
        }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Actions

    @objc private func textChanged(_ sender: UITextField) {
        encodedText = sender.text ?? ""
        if !encodedText.isEmpty {
            refreshQRCode()
        }
    }

    @objc private func shareTapped() {
        UIPasteboard.general.string = encodedText
        let activity = UIActivityViewController(
            activityItems: [encodedText],
            applicationActivities: nil
        )
        if let popover = activity.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(activity, animated: true)
    }
}
