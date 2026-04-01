import Foundation
import CryptoKit

/// Failure to persist the device private key to Keychain (connect would use an ephemeral identity).
public enum DeviceIdentityError: Error, Sendable {
    case persistenceFailed(underlying: Error)
}

/// Manages an Ed25519 device identity for Gateway authentication.
/// The key pair is generated once and persisted in Keychain.
public struct DeviceIdentity: Sendable {
    public let deviceId: String
    public let publicKeyBase64Url: String
    private let privateKeyRaw: Data

    private static let keychainKey = "gateway_device_private_key"

    // MARK: - Load or Create

    public static func loadOrCreate(keychain: KeychainStore = KeychainStore()) throws -> DeviceIdentity {
        if let existing = try? load(keychain: keychain) {
            return existing
        }
        return try create(keychain: keychain)
    }

    private static func load(keychain: KeychainStore) throws -> DeviceIdentity? {
        guard let b64 = try keychain.load(key: keychainKey),
              let rawData = Data(base64Encoded: b64) else {
            return nil
        }
        return try DeviceIdentity(rawRepresentation: rawData)
    }

    private static func create(keychain: KeychainStore) throws -> DeviceIdentity {
        let privateKey = Curve25519.Signing.PrivateKey()
        let raw = privateKey.rawRepresentation
        do {
            try keychain.save(key: keychainKey, value: raw.base64EncodedString())
        } catch {
            throw DeviceIdentityError.persistenceFailed(underlying: error)
        }
        return DeviceIdentity(privateKey: privateKey)
    }

    private init(privateKey: Curve25519.Signing.PrivateKey) {
        let publicKeyRaw = privateKey.publicKey.rawRepresentation
        self.privateKeyRaw = privateKey.rawRepresentation
        self.publicKeyBase64Url = Self.base64UrlEncode(publicKeyRaw)
        self.deviceId = SHA256.hash(data: publicKeyRaw)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    init(rawRepresentation: Data) throws {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
        self.init(privateKey: privateKey)
    }

    /// Import an external private key and persist it to Keychain.
    /// Used when scanning a QR code with a pre-approved device key.
    public static func importAndPersist(rawRepresentation: Data, keychain: KeychainStore = KeychainStore()) throws -> DeviceIdentity {
        let identity = try DeviceIdentity(rawRepresentation: rawRepresentation)
        try keychain.save(key: keychainKey, value: rawRepresentation.base64EncodedString())
        return identity
    }

    // MARK: - Sign Connect Request

    /// Build the `device` block for a Gateway connect request.
    public func signConnectRequest(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        token: String?,
        nonce: String,
        platform: String,
        deviceFamily: String?
    ) throws -> DeviceBlock {
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        let payload = buildPayloadV3(
            deviceId: deviceId,
            clientId: clientId,
            clientMode: clientMode,
            role: role,
            scopes: scopes,
            signedAtMs: signedAtMs,
            token: token,
            nonce: nonce,
            platform: platform,
            deviceFamily: deviceFamily
        )

        let payloadData = Data(payload.utf8)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
        let signature = try privateKey.signature(for: payloadData)
        let signatureBase64Url = Self.base64UrlEncode(signature)

        return DeviceBlock(
            id: deviceId,
            publicKey: publicKeyBase64Url,
            signature: signatureBase64Url,
            signedAt: signedAtMs,
            nonce: nonce
        )
    }

    // MARK: - Payload Construction (must match Gateway's buildDeviceAuthPayloadV3)

    private func buildPayloadV3(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String?,
        nonce: String,
        platform: String,
        deviceFamily: String?
    ) -> String {
        let scopesStr = scopes.joined(separator: ",")
        let tokenStr = token ?? ""
        let normalizedPlatform = Self.normalizeMetadata(platform)
        let normalizedFamily = Self.normalizeMetadata(deviceFamily)

        return [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopesStr,
            String(signedAtMs),
            tokenStr,
            nonce,
            normalizedPlatform,
            normalizedFamily
        ].joined(separator: "|")
    }

    /// Matches Gateway's `normalizeDeviceMetadataForAuth`: trim + lowercase ASCII
    private static func normalizeMetadata(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return "" }
        return trimmed.lowercased()
    }

    // MARK: - Base64URL

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decode a base64url string to Data.
    public static func base64UrlDecode(_ string: String) -> Data? {
        var b64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        return Data(base64Encoded: b64)
    }
}

// MARK: - Device Block (for connect request)

public struct DeviceBlock: Encodable, Sendable {
    public let id: String
    public let publicKey: String
    public let signature: String
    public let signedAt: Int64
    public let nonce: String
}
