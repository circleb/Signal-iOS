//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit
import SignalUI

class SSOAvatarView: UIView {
    
    enum Size {
        case small
        case medium
        case large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 40
            case .large: return 48
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            }
        }
    }
    
    private let size: Size
    private let userInfoStore: SSOUserInfoStore
    
    private let avatarImageView = UIImageView()
    private let initialsLabel = UILabel()
    
    init(size: Size = .medium, userInfoStore: SSOUserInfoStore = SSOUserInfoStoreImpl()) {
        self.size = size
        self.userInfoStore = userInfoStore
        super.init(frame: .zero)
        setupUI()
        updateAvatar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Configure avatar image view
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = size.dimension / 2
        avatarImageView.backgroundColor = Theme.primaryIconColor
        
        // Configure initials label
        initialsLabel.textAlignment = .center
        initialsLabel.font = .systemFont(ofSize: size.fontSize, weight: .medium)
        initialsLabel.textColor = Theme.backgroundColor
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.8
        
        // Layout
        addSubview(avatarImageView)
        addSubview(initialsLabel)
        
        avatarImageView.autoSetDimensions(to: CGSize(width: size.dimension, height: size.dimension))
        avatarImageView.autoPinEdgesToSuperviewEdges()
        initialsLabel.autoPinEdgesToSuperviewEdges()
    }
    
    // Override intrinsic content size to ensure the view maintains its square dimensions
    override var intrinsicContentSize: CGSize {
        return CGSize(width: size.dimension, height: size.dimension)
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return intrinsicContentSize
    }
    
    func updateAvatar() {
        guard let userInfo = userInfoStore.getUserInfo() else {
            showDefaultAvatar()
            return
        }
        
        if let name = userInfo.name, !name.isEmpty {
            showInitialsAvatar(name: name)
        } else if let email = userInfo.email, !email.isEmpty {
            showInitialsAvatar(name: email)
        } else {
            showDefaultAvatar()
        }
    }
    
    private func showInitialsAvatar(name: String) {
        let initials = extractInitials(from: name)
        initialsLabel.text = initials
        avatarImageView.image = nil
        avatarImageView.backgroundColor = generateAvatarColor(for: name)
    }
    
    private func showDefaultAvatar() {
        initialsLabel.text = "?"
        avatarImageView.image = nil
        avatarImageView.backgroundColor = Theme.secondaryBackgroundColor
    }
    
    private func extractInitials(from name: String) -> String {
        let components = name.components(separatedBy: .whitespaces)
        let initials = components.compactMap { $0.first?.uppercased() }
        
        if initials.count >= 2 {
            return String(initials[0]) + String(initials[1])
        } else if initials.count == 1 {
            return String(initials[0])
        } else {
            return "?"
        }
    }
    
    private func generateAvatarColor(for name: String) -> UIColor {
        // Always return blue for consistent branding
        return UIColor(red: 0.17, green: 0.42, blue: 0.93, alpha: 1.0) // Blue
    }
}
