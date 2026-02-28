//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Decodes a field as String when Directus returns either a string or number for ids.
private func decodeId<K: CodingKey>(from c: KeyedDecodingContainer<K>, forKey key: K) throws -> String {
    if let s = try? c.decode(String.self, forKey: key) { return s }
    if let n = try? c.decode(Int.self, forKey: key) { return String(n) }
    throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: c.codingPath + [key], debugDescription: "id must be String or Int"))
}

// MARK: - Subscription (notification list)

public struct DirectusSubscription: Codable, Equatable {
    public let id: String
    public let sort: Int?
    public let label: String
    public let slug: String
    public let isDefault: Bool
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case id, sort, label, slug, description
        case isDefault = "is_default"
    }
}

// MARK: - Enrolled device

public struct DirectusHcpEnrolledDevice: Codable, Equatable {
    public let id: String
    public let email: String
    public let dateCreated: String?
    public let userCreated: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case dateCreated = "date_created"
        case userCreated = "user_created"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try decodeId(from: c, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        dateCreated = try c.decodeIfPresent(String.self, forKey: .dateCreated)
        userCreated = try c.decodeIfPresent(String.self, forKey: .userCreated)
    }
}

// MARK: - Pivot (device <-> subscription link)

public struct DirectusMemberSubscriptionPivot: Codable, Equatable {
    public let id: String
    public let hcpEnrolledDevicesId: String
    public let subscriptionsId: String

    enum CodingKeys: String, CodingKey {
        case id
        case hcpEnrolledDevicesId = "hcp_enrolled_devices_id"
        case subscriptionsId = "Subscriptions_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try decodeId(from: c, forKey: .id)
        hcpEnrolledDevicesId = try decodeId(from: c, forKey: .hcpEnrolledDevicesId)
        subscriptionsId = try c.decode(String.self, forKey: .subscriptionsId)
    }
}

// MARK: - Directus API response wrappers

public struct DirectusSubscriptionResponse: Codable {
    public let data: [DirectusSubscription]
}

public struct DirectusHcpEnrolledDeviceResponse: Codable {
    public let data: DirectusHcpEnrolledDeviceArray
}

public enum DirectusHcpEnrolledDeviceArray: Codable {
    case single(DirectusHcpEnrolledDevice)
    case array([DirectusHcpEnrolledDevice])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(DirectusHcpEnrolledDevice.self) {
            self = .single(single)
        } else {
            self = .array(try container.decode([DirectusHcpEnrolledDevice].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    public var devices: [DirectusHcpEnrolledDevice] {
        switch self {
        case .single(let d): return [d]
        case .array(let a): return a
        }
    }
}

public struct DirectusMemberSubscriptionPivotResponse: Codable {
    public let data: DirectusMemberSubscriptionPivotArray
}

public enum DirectusMemberSubscriptionPivotArray: Codable {
    case single(DirectusMemberSubscriptionPivot)
    case array([DirectusMemberSubscriptionPivot])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(DirectusMemberSubscriptionPivot.self) {
            self = .single(single)
        } else {
            self = .array(try container.decode([DirectusMemberSubscriptionPivot].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    public var pivots: [DirectusMemberSubscriptionPivot] {
        switch self {
        case .single(let p): return [p]
        case .array(let a): return a
        }
    }
}

// MARK: - Directus error

public struct DirectusErrorResponse: Codable {
    public let errors: [DirectusErrorItem]?
}

public struct DirectusErrorItem: Codable {
    public let message: String?
    public let extensions: DirectusErrorExtensions?
}

public struct DirectusErrorExtensions: Codable {
    public let code: String?
}
