//
//  IPAHandler.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import Foundation
import CryptoKit
import Zip
import SwiftUI

final class AppFileHandler: NSObject, @unchecked Sendable {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	private let _uniqueWorkDir: URL
	var uniqueWorkDirPayload: URL?

	private var _ipa: URL
	private let _install: Bool
	private let _download: Download?
	private let _sourceProvenance: SourceAppProvenance?
	
	init(
		file ipa: URL,
		install: Bool = false,
		download: Download? = nil,
		sourceProvenance: SourceAppProvenance? = nil
	) {
		self._ipa = ipa
		self._install = install
		self._download = download
		self._sourceProvenance = sourceProvenance ?? download?.sourceProvenance
		self._uniqueWorkDir = _fileManager.temporaryDirectory
			.appendingPathComponent("FeatherImport_\(_uuid)", isDirectory: true)
		
		super.init()
	}
	
	func copy() async throws {
		try _fileManager.createDirectoryIfNeeded(at: _uniqueWorkDir)
		
		let destinationURL = _uniqueWorkDir.appendingPathComponent(_ipa.lastPathComponent)

		try _fileManager.removeFileIfNeeded(at: destinationURL)
		
		try _fileManager.copyItem(at: _ipa, to: destinationURL)
		_ipa = destinationURL
	}
	
	func extract() async throws {
		if _ipa.pathExtension == "ipa" {
			Zip.addCustomFileExtension("ipa")
		}
		if _ipa.pathExtension == "tipa" {
			Zip.addCustomFileExtension("tipa")
		}
		
		let download = self._download
		
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .utility).async {
				do {
					try Zip.unzipFile(
						self._ipa,
						destination: self._uniqueWorkDir,
						overwrite: true,
						password: nil,
						progress: { progress in
							if let download = download {
								DispatchQueue.main.async {
									download.unpackageProgress = progress
									
									#if !targetEnvironment(macCatalyst)
									if #available(iOS 26.0, *) {
										BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
									}
									#endif
								}
							}
						}
					)
					
					self.uniqueWorkDirPayload = self._uniqueWorkDir.appendingPathComponent("Payload")
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}
	
	func verify() async throws {
		guard
			let payloadURL = uniqueWorkDirPayload,
			let appURL = _fileManager.getPath(in: payloadURL, for: "app"),
			let bundle = Bundle(url: appURL)
		else {
			return
		}

		let info = bundle.infoDictionary ?? [:]
		let defaults = UserDefaults.standard
		var issues: [VerificationIssue] = []

		if let provenance = _sourceProvenance, defaults.object(forKey: "Feather.verification.security") as? Bool ?? true {
			if let identifier = bundle.bundleIdentifier, identifier != provenance.sourceAppIdentifier {
				issues.append(VerificationIssue(kind: .bundleID, expected: provenance.sourceAppIdentifier, actual: identifier))
			}

			if
				let expectedHash = provenance.sourceAppSHA256,
				let hash = try? _sha256(of: _ipa),
				hash.caseInsensitiveCompare(expectedHash) != .orderedSame
			{
				issues.append(VerificationIssue(kind: .hash))
			}

			if
				let expectedVersion = provenance.sourceAppVersion,
				let version = info["CFBundleShortVersionString"] as? String,
				version != expectedVersion
			{
				issues.append(VerificationIssue(kind: .version, expected: expectedVersion, actual: version))
			}

			if
				let expectedBuild = provenance.sourceAppBuildVersion,
				let build = info["CFBundleVersion"] as? String,
				build != expectedBuild
			{
				issues.append(VerificationIssue(kind: .buildVersion, expected: expectedBuild, actual: build))
			}
		}

		#if !targetEnvironment(macCatalyst)
		let system = ProcessInfo.processInfo.operatingSystemVersion
		let systemVersion = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
		if
			defaults.object(forKey: "Feather.verification.compatibility") as? Bool ?? true,
			let minimumVersion = info["MinimumOSVersion"] as? String,
			minimumVersion.compare(systemVersion, options: .numeric) == .orderedDescending
		{
			issues.append(VerificationIssue(kind: .minimumOS, expected: "iOS \(minimumVersion)", actual: "iOS \(systemVersion)"))
		}
		#endif

		guard !issues.isEmpty else { return }

		let appName = _sourceProvenance?.sourceAppName ?? bundle.name
		let sourceName = _sourceProvenance.map { $0.sourceRepositoryName ?? $0.sourceRepositoryURL.host ?? $0.sourceRepositoryURL.absoluteString }
		let appIcon = iconTest(appURL)

		// nobody to ask, so don't let it through
		guard
			let presenter = await MainActor.run(body: { UIApplication.topViewController() }),
			await VerificationWarningView.present(
				on: presenter,
				appName: appName,
				appIcon: appIcon,
				sourceName: sourceName,
				issues: issues
			)
		else {
			throw CancellationError()
		}
	}

	private func _sha256(of url: URL) throws -> String {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }

		var hasher = SHA256()
		while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
			hasher.update(data: chunk)
		}
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	func move() async throws {
		guard let payloadURL = uniqueWorkDirPayload else {
			throw ImportedFileHandlerError.payloadNotFound
		}
		
		let destinationURL = try await _directory()
		
		guard _fileManager.fileExists(atPath: payloadURL.path) else {
			throw ImportedFileHandlerError.payloadNotFound
		}
		
		try _fileManager.moveItem(at: payloadURL, to: destinationURL)
		
		try? _fileManager.removeItem(at: _uniqueWorkDir)
	}
	
	func addToDatabase() async throws {
		let app = try await _directory()
		
		guard let appUrl = _fileManager.getPath(in: app, for: "app") else {
			return
		}
		
		let bundle = Bundle(url: appUrl)
		let uuid = _uuid
		let sourceProvenance = _sourceProvenance
		let (name, identifier, version, icon) = (bundle?.name, bundle?.bundleIdentifier, bundle?.version, bundle?.iconFileName)

		// the context lives on the main queue, writing from here could drop the source metadata
		await MainActor.run {
			Storage.shared.addImported(
				uuid: uuid,
				source: sourceProvenance?.sourceRepositoryURL,
				appName: name,
				appIdentifier: identifier,
				appVersion: version,
				appIcon: icon
			) { _ in }

			if let sourceProvenance {
				Storage.shared.addSourceMetadata(
					for: uuid,
					kind: .imported,
					provenance: sourceProvenance
				)
				UpdateManager.shared.removeUpdates(
					sourceAppIdentifier: sourceProvenance.sourceAppIdentifier,
					installedVersion: sourceProvenance.sourceAppVersion
				)
			}
		}

		await Storage.shared.deleteOutdatedApps(
			identifier: bundle?.bundleIdentifier,
			version: bundle?.version,
			excluding: _uuid,
			signed: false
		)

		// updates from the library go straight to signing, then install
		if _download?.id.hasPrefix(AppUpdate.downloadIDPrefix) == true {
			let uuid = _uuid
			let isFeather = _download?.id == FeatherUpdate.downloadID
			DispatchQueue.main.async {
				NotificationCenter.default.post(
					name: Notification.Name("Feather.signUpdatedApp"),
					object: uuid,
					userInfo: ["isFeather": isFeather]
				)
			}
		}
	}
	
	private func _directory() async throws -> URL {
		// Documents/Feather/Unsigned/\(UUID)
		_fileManager.unsigned(_uuid)
	}
	
	func clean() async throws {
		try _fileManager.removeFileIfNeeded(at: _uniqueWorkDir)
	}
}

private enum ImportedFileHandlerError: Error {
	case payloadNotFound
}
