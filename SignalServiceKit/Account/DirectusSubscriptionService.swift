//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum DirectusSubscriptionError: Error {
    case notConfigured
    case invalidResponse
    case apiError(message: String, status: Int?, code: String?)
}

public protocol DirectusSubscriptionServiceProtocol: Sendable {
    func getSubscriptions() async throws -> [DirectusSubscription]
    func getEnrolledDevicesByEmail(_ email: String) async throws -> [DirectusHcpEnrolledDevice]
    func getDeviceSubscriptionPivotsByEmail(_ email: String) async throws -> [DirectusMemberSubscriptionPivot]
    func createDeviceSubscriptionPivot(deviceId: String, subscriptionId: String) async throws -> DirectusMemberSubscriptionPivot
    func deleteDeviceSubscriptionPivot(pivotId: String) async throws
    func saveUserSubscriptions(email: String, selectedSubscriptionIds: Set<String>) async throws
}

public final class DirectusSubscriptionService: DirectusSubscriptionServiceProtocol {

    private let baseURL: String
    private let apiKey: String

    public init(baseURL: String? = nil, apiKey: String? = nil) {
        self.baseURL = (baseURL ?? DirectusConfig.baseURL).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey ?? DirectusConfig.apiKey
    }

    private var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty
    }

    private func makeURL(path: String, query: String? = nil) throws -> String {
        guard isConfigured else { throw DirectusSubscriptionError.notConfigured }
        var url = "\(baseURL)/items\(path)"
        if let q = query, !q.isEmpty {
            url += (path.contains("?") ? "&" : "?") + q
        }
        return url
    }

    private var authHeaders: HttpHeaders {
        var headers = HttpHeaders()
        headers.addHeader("Authorization", value: "Bearer \(apiKey)", overwriteOnConflict: true)
        headers.addHeader("Content-Type", value: "application/json", overwriteOnConflict: true)
        return headers
    }

    private func session() -> OWSURLSession {
        OWSURLSession(
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching,
            canUseSignalProxy: false
        )
    }

    private func handleErrorResponse(_ response: HTTPResponse) throws -> Never {
        let status = response.responseStatusCode
        var message = "Request failed with status \(status)"
        var code: String?
        if let data = response.responseBodyData,
           let err = try? JSONDecoder().decode(DirectusErrorResponse.self, from: data),
           let first = err.errors?.first {
            message = first.message ?? message
            code = first.extensions?.code
        }
        throw DirectusSubscriptionError.apiError(message: message, status: status, code: code)
    }

    public func getSubscriptions() async throws -> [DirectusSubscription] {
        let url = try makeURL(path: "/Subscriptions")
        let response = try await session().performRequest(url, method: .get, headers: authHeaders)
        guard let data = response.responseBodyData else { throw DirectusSubscriptionError.invalidResponse }
        let decoded = try JSONDecoder().decode(DirectusSubscriptionResponse.self, from: data)
        return decoded.data
    }

    public func getEnrolledDevicesByEmail(_ email: String) async throws -> [DirectusHcpEnrolledDevice] {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        let url = try makeURL(path: "/hcp_enrolled_devices", query: "filter[email][_eq]=\(encoded)")
        let response = try await session().performRequest(url, method: .get, headers: authHeaders)
        guard let data = response.responseBodyData else { throw DirectusSubscriptionError.invalidResponse }
        let decoded = try JSONDecoder().decode(DirectusHcpEnrolledDeviceResponse.self, from: data)
        return decoded.data.devices
    }

    public func getDeviceSubscriptionPivotsByEmail(_ email: String) async throws -> [DirectusMemberSubscriptionPivot] {
        let devices = try await getEnrolledDevicesByEmail(email)
        if devices.isEmpty { return [] }
        let deviceIds = devices.map(\.id).joined(separator: ",")
        let url = try makeURL(path: "/hcp_enrolled_devices_Subscriptions", query: "filter[hcp_enrolled_devices_id][_in]=\(deviceIds)")
        let response = try await session().performRequest(url, method: .get, headers: authHeaders)
        guard let data = response.responseBodyData else { throw DirectusSubscriptionError.invalidResponse }
        let decoded = try JSONDecoder().decode(DirectusMemberSubscriptionPivotResponse.self, from: data)
        return decoded.data.pivots
    }

    public func createDeviceSubscriptionPivot(deviceId: String, subscriptionId: String) async throws -> DirectusMemberSubscriptionPivot {
        let url = try makeURL(path: "/hcp_enrolled_devices_Subscriptions")
        let body: [String: String] = [
            "hcp_enrolled_devices_id": deviceId,
            "Subscriptions_id": subscriptionId
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await session().performRequest(url, method: .post, headers: authHeaders, body: bodyData)
        guard let data = response.responseBodyData else { throw DirectusSubscriptionError.invalidResponse }
        let decoded = try JSONDecoder().decode(DirectusMemberSubscriptionPivotResponse.self, from: data)
        let pivots = decoded.data.pivots
        guard let first = pivots.first else { throw DirectusSubscriptionError.invalidResponse }
        return first
    }

    public func deleteDeviceSubscriptionPivot(pivotId: String) async throws {
        let url = try makeURL(path: "/hcp_enrolled_devices_Subscriptions/\(pivotId)")
        _ = try await session().performRequest(url, method: .delete, headers: authHeaders)
    }

    public func saveUserSubscriptions(email: String, selectedSubscriptionIds: Set<String>) async throws {
        let devices = try await getEnrolledDevicesByEmail(email)
        if devices.isEmpty {
            Logger.warn("No enrolled devices found for email: \(email)")
            return
        }
        let existingPivots = try await getDeviceSubscriptionPivotsByEmail(email)

        var deviceSubscriptions: [String: Set<String>] = [:]
        for d in devices { deviceSubscriptions[d.id] = [] }
        for p in existingPivots {
            deviceSubscriptions[p.hcpEnrolledDevicesId, default: []].insert(p.subscriptionsId)
        }

        var toAdd: [(deviceId: String, subscriptionId: String)] = []
        var toRemove: [DirectusMemberSubscriptionPivot] = []

        for device in devices {
            let existing = deviceSubscriptions[device.id] ?? []
            for subId in selectedSubscriptionIds where !existing.contains(subId) {
                toAdd.append((device.id, subId))
            }
            for subId in existing where !selectedSubscriptionIds.contains(subId) {
                if let pivot = existingPivots.first(where: { $0.hcpEnrolledDevicesId == device.id && $0.subscriptionsId == subId }) {
                    toRemove.append(pivot)
                }
            }
        }

        for item in toAdd {
            _ = try await createDeviceSubscriptionPivot(deviceId: item.deviceId, subscriptionId: item.subscriptionId)
        }
        for pivot in toRemove {
            try await deleteDeviceSubscriptionPivot(pivotId: pivot.id)
        }
    }
}
