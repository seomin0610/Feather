//
//  CertificateFileHandler.swift
//  Feather
//
//  Created by samara on 15.04.2025.
//

import Foundation
import OSLog
import ZsignC

final class CertificateFileHandler: NSObject {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	
	private let _key: URL
	private let _provision: URL
	private let _keyPassword: String?
	private let _certNickname: String?
	private let _isDefault: Bool
	
	private var _certPair: Certificate?
	
	init(
		key: URL,
		provision: URL,
		password: String? = nil,
		nickname: String? = nil,
		isDefault: Bool = false
	) {
		self._key = key
		self._provision = provision
		self._keyPassword = password
		self._certNickname = nickname
		self._isDefault = isDefault
		
		_certPair = CertificateReader(provision).decoded
		
		super.init()
	}
	
	func copy() async throws {
		guard let certPair = _certPair else {
			throw CertificateFileHandlerError.certNotValid
		}
		
		// a p12 without its own certificate gets one picked from the profile by zsign, so only a present one can mismatch
		if
			let certificate = p12_certificate(_key.path, _keyPassword ?? ""),
			!(certPair.DeveloperCertificates ?? []).contains(certificate)
		{
			throw CertificateFileHandlerError.provisionMismatch
		}
		
		let destinationURL = try await _directory()

		try _fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
		try _fileManager.copyItem(at: _key, to: destinationURL.appendingPathComponent(_key.lastPathComponent))
		try _fileManager.copyItem(at: _provision, to: destinationURL.appendingPathComponent(_provision.lastPathComponent))
	}
	
	func addToDatabase() async throws {
		
		Storage.shared.addCertificate(
			uuid: _uuid,
			password: _keyPassword,
			nickname: _certNickname,
			ppq: _certPair?.PPQCheck ?? false,
			expiration: _certPair?.ExpirationDate ?? Date(),
			isDefault: _isDefault
		) { _ in
			Logger.misc.info("[\(self._uuid)] Added to database")
		}
	}
	
	private func _directory() async throws -> URL {
		// Documents/Feather/Certificates/\(UUID)
		_fileManager.certificates(_uuid)
	}
}

private enum CertificateFileHandlerError: Error, LocalizedError {
	case certNotValid
	case provisionMismatch
	
	var errorDescription: String? {
		switch self {
		case .certNotValid: .localized("The provisioning profile could not be read.")
		case .provisionMismatch: .localized("This certificate is not in the provisioning profile. Use the p12 and mobileprovision that were issued together.")
		}
	}
}
