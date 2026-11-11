//
//  FavoriteAddCollectionViewCell.swift
//  Reynard
//
//  Trailing "+" tile of the Edge start page favorites grid. It wraps onto the
//  next row like any other favorite when the current row is full.
//

import UIKit

final class FavoriteAddCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "FavoriteAddCollectionViewCell"
    
    private enum UX {
        static let cornerRadius: CGFloat = 17
        static let titleHeight: CGFloat = 34
        static let symbolSize: CGFloat = 24
    }
    
    private let tileView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = EdgeHomepagePalette.chip
        view.layer.cornerRadius = UX.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = EdgeHomepagePalette.UX.hairline
        view.layer.borderColor = EdgeHomepagePalette.hairline.cgColor
        return view
    }()
    
    private let plusView: UIImageView = {
        let imageView = UIImageView(image: UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: UX.symbolSize, weight: .regular)
        ))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = EdgeHomepagePalette.secondaryText
        imageView.contentMode = .center
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.text = NSLocalizedString("Add", comment: "Homepage favorites add tile")
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = NSLocalizedString("Add to Favorites", comment: "")
        contentView.addSubview(tileView)
        tileView.addSubview(plusView)
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            tileView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tileView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            tileView.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            tileView.heightAnchor.constraint(equalTo: tileView.widthAnchor),
            
            plusView.centerXAnchor.constraint(equalTo: tileView.centerXAnchor),
            plusView.centerYAnchor.constraint(equalTo: tileView.centerYAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: tileView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isHighlighted: Bool {
        didSet {
            tileView.alpha = isHighlighted ? 0.6 : 1
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        tileView.layer.borderColor = EdgeHomepagePalette.hairline.cgColor
    }
    
    func configure(titleColor: UIColor) {
        titleLabel.textColor = titleColor
    }
}
