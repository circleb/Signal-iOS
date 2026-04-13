import SwiftUI

struct AvatarView: View {
    let name: String?
    var size: CGFloat = 40

    private var initials: String {
        guard let name, !name.isEmpty else { return "?" }
        let parts = name.components(separatedBy: .whitespaces).compactMap { $0.first?.uppercased() }
        if parts.count >= 2 { return parts[0] + parts[1] }
        return parts.first ?? "?"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.hcpBlue)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
