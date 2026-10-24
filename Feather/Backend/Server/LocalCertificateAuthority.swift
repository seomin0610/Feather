//
//  LocalCertificateAuthority.swift
//  Feather
//
//  Created by Jeongmin on 25.10.2026.
//

import Crypto
import Foundation
import Security
import SwiftASN1
import X509

enum LocalCertificateAuthority {
	// iOS refuses install manifests on 127.0.0.1 or localhost
	static let host = "127-0-0-1.sslip.io"

	private static let _keychainService = "Feather.localCertificateAuthority"
	private static let _caKeyAccount = "caKey"
	private static let _caCertificateAccount = "caCertificate"
	private static let _lock = NSLock()

	// iOS rejects server certificates valid for longer than 825 days
	private static let _serverValidity: TimeInterval = 397 * 24 * 60 * 60
	private static let _serverRenewalMargin: TimeInterval = 30 * 24 * 60 * 60

	private static var _directory: URL {
		URL.applicationSupportDirectory.appendingPathComponent("LocalCertificateAuthority", isDirectory: true)
	}

	private static var _serverCertificateURL: URL { _directory.appendingPathComponent("server.crt") }
	private static var _serverKeyURL: URL { _directory.appendingPathComponent("server.pem") }

	private static func _authority() throws -> (key: P256.Signing.PrivateKey, certificate: X509.Certificate) {
		if
			let keyData = _readKeychain(_caKeyAccount),
			let certificateData = _readKeychain(_caCertificateAccount),
			let key = try? P256.Signing.PrivateKey(rawRepresentation: keyData),
			let certificate = try? X509.Certificate(derEncoded: Array(certificateData)),
			certificate.notValidAfter > Date(),
			(try? certificate.extensions.nameConstraints?.permittedDNSDomains.contains(host)) == true
		{
			return (key, certificate)
		}

		let key = P256.Signing.PrivateKey()
		let publicKey = X509.Certificate.PublicKey(key.publicKey)
		let name = try DistinguishedName {
			CommonName("Feather Local CA")
			OrganizationName("Feather")
		}
		let now = Date()
		let certificate = try X509.Certificate(
			version: .v3,
			serialNumber: .init(),
			publicKey: publicKey,
			notValidBefore: now.addingTimeInterval(-60 * 60),
			notValidAfter: now.addingTimeInterval(20 * 365 * 24 * 60 * 60),
			issuer: name,
			subject: name,
			extensions: try X509.Certificate.Extensions {
				Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
				Critical(KeyUsage(keyCertSign: true, cRLSign: true))
				Critical(NameConstraints(
					permittedDNSDomains: [host, "localhost"],
					permittedIPRanges: [ASN1OctetString(contentBytes: [127, 0, 0, 1, 255, 255, 255, 255])]
				))
				SubjectKeyIdentifier(hash: publicKey)
			},
			issuerPrivateKey: .init(key)
		)

		var serializer = DER.Serializer()
		try serializer.serialize(certificate)
		try _writeKeychain(key.rawRepresentation, account: _caKeyAccount)
		try _writeKeychain(Data(serializer.serializedBytes), account: _caCertificateAccount)

		try? FileManager.default.removeItem(at: _serverCertificateURL)
		try? FileManager.default.removeItem(at: _serverKeyURL)

		return (key, certificate)
	}

	static func authorityCertificateData() throws -> Data {
		_lock.lock()
		defer { _lock.unlock() }

		var serializer = DER.Serializer()
		try serializer.serialize(try _authority().certificate)
		return Data(serializer.serializedBytes)
	}

	static func serverCertificate() throws -> (certificate: URL, key: URL) {
		_lock.lock()
		defer { _lock.unlock() }

		let authority = try _authority()

		if
			let pem = try? String(contentsOf: _serverCertificateURL, encoding: .utf8),
			let certificate = try? X509.Certificate(pemEncoded: pem),
			certificate.issuer == authority.certificate.subject,
			certificate.notValidAfter > Date().addingTimeInterval(_serverRenewalMargin),
			FileManager.default.fileExists(atPath: _serverKeyURL.path)
		{
			return (_serverCertificateURL, _serverKeyURL)
		}

		let key = P256.Signing.PrivateKey()
		let now = Date()
		let certificate = try X509.Certificate(
			version: .v3,
			serialNumber: .init(),
			publicKey: .init(key.publicKey),
			notValidBefore: now.addingTimeInterval(-60 * 60),
			notValidAfter: now.addingTimeInterval(_serverValidity),
			issuer: authority.certificate.subject,
			subject: try DistinguishedName { CommonName(host) },
			extensions: try X509.Certificate.Extensions {
				Critical(BasicConstraints.notCertificateAuthority)
				Critical(KeyUsage(digitalSignature: true))
				try ExtendedKeyUsage([.serverAuth])
				SubjectAlternativeNames([
					.dnsName(host),
					.dnsName("localhost"),
					.ipAddress(ASN1OctetString(contentBytes: [127, 0, 0, 1]))
				])
				AuthorityKeyIdentifier(keyIdentifier: try? authority.certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
			},
			issuerPrivateKey: .init(authority.key)
		)

		let chain = try certificate.serializeAsPEM().pemString + "\n" + authority.certificate.serializeAsPEM().pemString + "\n"

		try FileManager.default.createDirectory(at: _directory, withIntermediateDirectories: true)
		try Data(chain.utf8).write(to: _serverCertificateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
		try Data(key.pemRepresentation.utf8).write(to: _serverKeyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

		return (_serverCertificateURL, _serverKeyURL)
	}

	static func isTrusted() -> Bool {
		guard
			let files = try? serverCertificate(),
			let pem = try? String(contentsOf: files.certificate, encoding: .utf8)
		else {
			return false
		}

		let certificates = pem
			.components(separatedBy: "-----END CERTIFICATE-----")
			.compactMap { try? X509.Certificate(pemEncoded: $0 + "-----END CERTIFICATE-----") }
			.compactMap { certificate -> SecCertificate? in
				var serializer = DER.Serializer()
				guard (try? serializer.serialize(certificate)) != nil else { return nil }
				return SecCertificateCreateWithData(nil, Data(serializer.serializedBytes) as CFData)
			}

		var trust: SecTrust?
		guard
			!certificates.isEmpty,
			SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust) == errSecSuccess,
			let trust
		else {
			return false
		}

		return SecTrustEvaluateWithError(trust, nil)
	}

	static func profileData() throws -> Data {
		let bundleIdentifier = Bundle.main.bundleIdentifier ?? "thewonderofyou.Feather"
		let profile: [String: Any] = [
			"PayloadContent": [[
				"PayloadCertificateFileName": "FeatherLocalCA.cer",
				"PayloadContent": try authorityCertificateData(),
				"PayloadDisplayName": "Feather Local CA",
				"PayloadIdentifier": "\(bundleIdentifier).localca.certificate",
				"PayloadType": "com.apple.security.root",
				"PayloadUUID": UUID().uuidString,
				"PayloadVersion": 1
			]],
			"PayloadDescription": "Lets Feather install apps from its own server on this device. It is only valid for \(host), localhost and 127.0.0.1.",
			"PayloadDisplayName": "Feather Local Certificate",
			"PayloadIdentifier": "\(bundleIdentifier).localca",
			"PayloadRemovalDisallowed": false,
			"PayloadType": "Configuration",
			"PayloadUUID": UUID().uuidString,
			"PayloadVersion": 1
		]

		return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
	}

	private static func _readKeychain(_ account: String) -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: _keychainService,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]

		var result: AnyObject?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
		return result as? Data
	}

	private static func _writeKeychain(_ data: Data, account: String) throws {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: _keychainService,
			kSecAttrAccount as String: account
		]
		SecItemDelete(query as CFDictionary)

		var attributes = query
		attributes[kSecValueData as String] = data
		attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

		let status = SecItemAdd(attributes as CFDictionary, nil)
		guard status == errSecSuccess else {
			throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
		}
	}
}
