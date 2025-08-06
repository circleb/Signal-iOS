//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum WebAppsError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case invalidURL
    case cacheError
    case noWebAppsAvailable

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidURL:
            return "Invalid web app URL"
        case .cacheError:
            return "Failed to cache web apps"
        case .noWebAppsAvailable:
            return "No web apps available"
        }
    }
} 
