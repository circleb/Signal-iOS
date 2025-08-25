//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import SignalUI

struct BlockedMessageView: View {
    let blockedURL: String
    let onGoBack: () -> Void
    let onRequestAccess: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            // Title
            Text("Website Blocked")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // Blocked URL
            Text(blockedURL)
                .font(.body)
                .foregroundColor(.secondary)
                        
            // Buttons
            VStack(spacing: 12) {
                Button(action: onRequestAccess) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Request Access")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.Signal.accent)
                    .cornerRadius(12)
                }
                
                Button(action: onGoBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Go Back")
                    }
                    .font(.headline)
                    .foregroundColor(.Signal.accent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.Signal.accent.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .background(Color.Signal.groupedBackground)
    }
}

#Preview {
    BlockedMessageView(
        blockedURL: "https://example.com",
        onGoBack: {},
        onRequestAccess: {}
    )
}
