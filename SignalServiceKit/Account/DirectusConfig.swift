//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DirectusConfig {
    /// Base URL for the Directus API (e.g. https://your-directus.instance).
    /// Configure via Info.plist key "DirectusBaseURL" or set here for development.
    public static var baseURL: String {
        if let url = Bundle.main.object(forInfoDictionaryKey: "DirectusBaseURL") as? String, !url.isEmpty {
            return url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return _fallbackBaseURL
    }

    /// API key for Directus (Bearer token). Configure via Info.plist "DirectusAPIKey" or build setting.
    public static var apiKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "DirectusAPIKey") as? String, !key.isEmpty {
            return key
        }
        return _fallbackAPIKey
    }

    /// Fallback values when Info.plist is not set (e.g. empty for release; set in xcconfig for dev).
    private static let _fallbackBaseURL = ""
    private static let _fallbackAPIKey = ""
}
