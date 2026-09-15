//
//  UpdateManager.swift
//  Feather
//
//  Created by Dominic on 24.05.2026.
//

import AltSourceKit
import CoreData
import Foundation
import NimbleJSON

struct AppUpdate: Identifiable, Equatable {
	let id: String
	let localUUID: String
	let localVersion: String?
	let remoteVersion: String
	let appName: String
	let bundleIdentifier: String
	let downloadURL: URL
	let sourceURL: URL
	let sourceProvenance: SourceAppProvenance
	let isSigned: Bool
	let releaseNotes: String?
	let versionDate: Date?
	let size: Int64?

	static let downloadIDPrefix = "FeatherManualDownload_Update_"

	var downloadID: String {
		"\(Self.downloadIDPrefix)\(localUUID)"
	}
}

/// A newer release of Feather itself, installed through the signer server since it can't update itself.
struct FeatherUpdate: Equatable {
	let localVersion: String?
	let remoteVersion: String
	let downloadURL: URL
	let releaseNotes: String?
	let versionDate: Date?
	let size: Int64?
	let sourceProvenance: SourceAppProvenance

	static let repositoryURL = URL(string: "https://raw.githubusercontent.com/seomin0610/Feather/main/app-repo.json")!
	static let downloadID = "\(AppUpdate.downloadIDPrefix)Feather"
}

@MainActor
final class UpdateManager: ObservableObject {
	static let shared = UpdateManager()
	
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	
	@Published private(set) var updates: [String: AppUpdate] = [:]
	@Published private(set) var isChecking = false
	@Published private(set) var lastCheckedDate: Date?
	@Published private(set) var featherUpdate: FeatherUpdate?
	
	private let _dataService = NBFetchService()
	
	private init() {}
	
	func update(for app: AppInfoPresentable) -> AppUpdate? {
		guard let uuid = app.uuid else { return nil }
		return updates[uuid]
	}

	/// One update per app, preferring unsigned copies since those can be signed again after downloading.
	var pendingUpdates: [AppUpdate] {
		var seen = Set<String>()
		return updates.values
			.sorted { ($0.isSigned ? 1 : 0, $0.localUUID) < ($1.isSigned ? 1 : 0, $1.localUUID) }
			.filter { seen.insert($0.bundleIdentifier).inserted }
			.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
	}

	func checkForUpdatesIfNeeded(interval: TimeInterval = 60 * 30) async {
		if let lastCheckedDate, Date().timeIntervalSince(lastCheckedDate) < interval {
			return
		}

		let context = Storage.shared.context
		let signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
		let importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()
		let localApps: [AppInfoPresentable] =
			((try? context.fetch(signedRequest)) ?? []) +
			((try? context.fetch(importedRequest)) ?? [])

		await checkForUpdates(
			sources: Storage.shared.getSources(),
			localApps: localApps
		)
	}

	func startUpdate(_ update: AppUpdate) {
		_ = DownloadManager.shared.startDownload(
			from: update.downloadURL,
			id: update.downloadID,
			sourceProvenance: update.sourceProvenance
		)
	}

	/// Matches by URL too, so every library row for the same update reflects one shared download.
	func download(for update: AppUpdate) -> Download? {
		DownloadManager.shared.downloads.first {
			$0.id == update.downloadID || $0.url == update.downloadURL
		}
	}

	func updateAll() {
		if let featherUpdate, download(for: featherUpdate) == nil {
			startFeatherUpdate(featherUpdate)
		}
		for update in pendingUpdates where download(for: update) == nil {
			startUpdate(update)
		}
	}

	var updateCount: Int {
		pendingUpdates.count + (featherUpdate == nil ? 0 : 1)
	}

	func download(for update: FeatherUpdate) -> Download? {
		DownloadManager.shared.downloads.first {
			$0.id == FeatherUpdate.downloadID || $0.url == update.downloadURL
		}
	}

	func startFeatherUpdate(_ update: FeatherUpdate) {
		_ = DownloadManager.shared.startDownload(
			from: update.downloadURL,
			id: FeatherUpdate.downloadID,
			sourceProvenance: update.sourceProvenance
		)
	}

	private func _findFeatherUpdate() async -> FeatherUpdate? {
		guard let repository = await _fetchRepository(from: FeatherUpdate.repositoryURL) else {
			return featherUpdate
		}

		let bundleIdentifier = Bundle.main.bundleIdentifier
		let localVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

		guard
			let remoteApp = repository.apps.first(where: { $0.id == bundleIdentifier }) ?? repository.apps.first,
			let remoteVersion = remoteApp.currentVersion,
			let downloadURL = remoteApp.currentDownloadUrl,
			remoteVersion.compare(localVersion ?? "0", options: .numeric) == .orderedDescending,
			let provenance = SourceAppProvenance(
				sourceURL: FeatherUpdate.repositoryURL,
				repository: repository,
				app: remoteApp
			)
		else {
			return nil
		}

		return FeatherUpdate(
			localVersion: localVersion,
			remoteVersion: remoteVersion,
			downloadURL: downloadURL,
			releaseNotes: remoteApp.currentAppVersion?.localizedDescription ?? remoteApp.versionDescription,
			versionDate: remoteApp.currentDate?.date,
			size: remoteApp.currentAppVersion?.size.map { Int64($0) } ?? remoteApp.size,
			sourceProvenance: provenance
		)
	}

	func removeUpdate(for uuid: String?) {
		guard let uuid else { return }
		updates[uuid] = nil
	}

	/// Clears updates satisfied by a newly imported version.
	func removeUpdates(sourceAppIdentifier: String, installedVersion: String?) {
		updates = updates.filter {
			!($0.value.bundleIdentifier == sourceAppIdentifier && $0.value.remoteVersion == installedVersion)
		}

		if
			let featherUpdate,
			featherUpdate.sourceProvenance.sourceAppIdentifier == sourceAppIdentifier,
			featherUpdate.remoteVersion == installedVersion
		{
			self.featherUpdate = nil
		}
	}

	func checkForUpdates(
		sources: [AltSource],
		localApps: [AppInfoPresentable]
	) async {
		guard !isChecking else { return }
		
		isChecking = true
		defer {
			isChecking = false
			lastCheckedDate = Date()
		}
		
		let repositories = await _fetchRepositories(from: sources)
		updates = _findUpdates(repositories: repositories, localApps: localApps)
		featherUpdate = await _findFeatherUpdate()
	}
	
	private func _fetchRepositories(from sources: [AltSource]) async -> [(AltSource, ASRepository)] {
		var repositories: [(AltSource, ASRepository)] = []
		
		for source in sources {
			guard let url = source.sourceURL else {
				continue
			}
			
			guard let repository = await _fetchRepository(from: url) else {
				continue
			}
			
			repositories.append((source, repository))
		}
		
		return repositories
	}
	
	private func _fetchRepository(from url: URL) async -> ASRepository? {
		await withCheckedContinuation { continuation in
			_dataService.fetch(from: url) { (result: RepositoryDataHandler) in
				switch result {
				case .success(let repository):
					continuation.resume(returning: repository)
				case .failure:
					continuation.resume(returning: nil)
				}
			}
		}
	}
	
	private func _findUpdates(
		repositories: [(AltSource, ASRepository)],
		localApps: [AppInfoPresentable]
	) -> [String: AppUpdate] {
		var foundUpdates: [String: AppUpdate] = [:]
		let metadataByUUID = Storage.shared.getSourceMetadata().reduce(into: [String: AppSourceMetadata]()) {
			$0[$1.appUUID] = $1
		}
		let metadataCandidates = localApps.compactMap { app -> SourceMetadataCandidate? in
			guard
				let uuid = app.uuid,
				let metadata = metadataByUUID[uuid]
			else {
				return nil
			}
			return SourceMetadataCandidate(appUUID: uuid, app: app, metadata: metadata)
		}
		
		for localApp in localApps {
			guard let localUUID = localApp.uuid else {
				continue
			}
			
			let sourceAppIdentifier: String
			let sourceAppVersion: String?
			let storedSourceURL: URL
			if let directMetadata = metadataByUUID[localUUID] {
				guard
					let metadataSourceAppIdentifier = directMetadata.sourceAppIdentifier,
					let metadataSourceURL = directMetadata.sourceRepositoryURL
				else {
					continue
				}
				
				sourceAppIdentifier = metadataSourceAppIdentifier
				sourceAppVersion = directMetadata.sourceAppVersion
				storedSourceURL = metadataSourceURL
			} else if let fallback = _fallbackMetadataCandidate(
				for: localApp,
				localUUID: localUUID,
				candidates: metadataCandidates
			) {
				guard
					let metadataSourceAppIdentifier = fallback.metadata.sourceAppIdentifier,
					let metadataSourceURL = fallback.metadata.sourceRepositoryURL
				else {
					continue
				}
				
				sourceAppIdentifier = metadataSourceAppIdentifier
				sourceAppVersion = fallback.metadata.sourceAppVersion
				storedSourceURL = metadataSourceURL
				Storage.shared.copySourceMetadata(
					from: fallback.appUUID,
					to: localUUID,
					kind: localApp.isSigned ? .signed : .imported
				)
			} else if
				let localSourceURL = localApp.source,
				let localIdentifier = localApp.identifier
			{
				sourceAppIdentifier = localIdentifier
				sourceAppVersion = localApp.version
				storedSourceURL = localSourceURL
			} else {
				continue
			}
			
			for (source, repository) in repositories {
				guard let sourceURL = source.sourceURL else {
					continue
				}
				
				guard _matchesStoredRepository(storedSourceURL: storedSourceURL, sourceURL: sourceURL) else {
					continue
				}
				
				guard let remoteApp = repository.apps.first(where: { $0.id == sourceAppIdentifier }) else {
					continue
				}
				
				guard let remoteVersion = remoteApp.currentVersion, !remoteVersion.isEmpty else {
					continue
				}
				
				guard remoteVersion != sourceAppVersion else {
					continue
				}
				
				guard let downloadURL = remoteApp.currentDownloadUrl else {
					continue
				}
				
				guard let provenance = SourceAppProvenance(
					sourceURL: sourceURL,
					repository: repository,
					app: remoteApp
				) else {
					continue
				}
				
				foundUpdates[localUUID] = AppUpdate(
					id: localUUID,
					localUUID: localUUID,
					localVersion: sourceAppVersion ?? localApp.version,
					remoteVersion: remoteVersion,
					appName: remoteApp.currentName,
					bundleIdentifier: sourceAppIdentifier,
					downloadURL: downloadURL,
					sourceURL: sourceURL,
					sourceProvenance: provenance,
					isSigned: localApp.isSigned,
					releaseNotes: remoteApp.currentAppVersion?.localizedDescription ?? remoteApp.versionDescription,
					versionDate: remoteApp.currentDate?.date,
					size: remoteApp.currentAppVersion?.size.map { Int64($0) } ?? remoteApp.size
				)
				break
			}
		}
		
		return foundUpdates
	}
	
	private func _matchesStoredRepository(
		storedSourceURL: URL,
		sourceURL: URL
	) -> Bool {
		_normalizedSourceURL(storedSourceURL) == _normalizedSourceURL(sourceURL)
	}
	
	private func _normalizedSourceURL(_ url: URL) -> String {
		var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		let scheme = components?.scheme?.lowercased()
		let host = components?.host?.lowercased()
		components?.scheme = scheme
		components?.host = host
		components?.fragment = nil
		
		let normalized = components?.url ?? url
		let absoluteString = normalized.absoluteString
		return absoluteString.hasSuffix("/") ? String(absoluteString.dropLast()) : absoluteString
	}
	
	private func _fallbackMetadataCandidate(
		for localApp: AppInfoPresentable,
		localUUID: String,
		candidates: [SourceMetadataCandidate]
	) -> SourceMetadataCandidate? {
		guard
			localApp.isSigned,
			let localIdentifier = localApp.identifier,
			let localVersion = localApp.version
		else {
			return nil
		}
		
		return candidates.first {
			$0.appUUID != localUUID &&
			!$0.app.isSigned &&
			$0.app.identifier == localIdentifier &&
			$0.app.version == localVersion
		}
	}
}

private struct SourceMetadataCandidate {
	let appUUID: String
	let app: AppInfoPresentable
	let metadata: AppSourceMetadata
}
