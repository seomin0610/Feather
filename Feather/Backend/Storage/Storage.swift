//
//  Persistence.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import Foundation

// MARK: - Storage
final class Storage: ObservableObject {
	static let shared = Storage()
	let container: NSPersistentContainer
	
	private let _name: String = "Feather"

	init(inMemory: Bool = false) {
		container = NSPersistentContainer(name: _name)

		if inMemory {
			container.persistentStoreDescriptions.first?.url =
				URL(fileURLWithPath: "/dev/null")
		} else {
			_replaceStoreIfPending()
		}
		
		container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
		container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true

		_loadPersistentStoreAggressively()
		container.viewContext.automaticallyMergesChangesFromParent = true
		container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
	}

	// MARK: FeatherPlus
	/// FeatherPlus keeps its database in Documents, Feather keeps it in Application Support.
	/// If this file exists, the previous install was FeatherPlus and its data has not been migrated yet.
	static let featherPlusStoreURL = URL.documentsDirectory.appendingPathComponent("Feather.sqlite")
	static let featherPlusMigrationDeclinedKey = "Feather.featherPlusMigrationDeclined"
	static let pendingFeatherPlusMigrationKey = "Feather.pendingFeatherPlusMigration"
	
	static var hasFeatherPlusData: Bool {
		FileManager.default.fileExists(atPath: featherPlusStoreURL.path)
	}
	
	// MARK: Import / Export
	static let pendingImportStoreURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("FeatherImport.sqlite")

	func exportDatabase() throws -> URL {
		if context.hasChanges {
			try context.save()
		}

		guard let storeURL = container.persistentStoreDescriptions.first?.url else {
			throw CocoaError(.fileNoSuchFile)
		}

		let date = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("Feather-\(date).sqlite")
		_removeStoreFiles(at: url)

		try container.persistentStoreCoordinator.replacePersistentStore(
			at: url,
			destinationOptions: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]],
			withPersistentStoreFrom: storeURL,
			sourceOptions: nil,
			ofType: NSSQLiteStoreType
		)
		return url
	}

	static func validateDatabase(at url: URL) throws {
		let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
		guard
			let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any],
			["Imported", "Signed", "CertificatePair"].allSatisfy({ hashes[$0] != nil })
		else {
			throw CocoaError(.fileReadCorruptFile)
		}
	}

	static func stageDatabaseImport(from url: URL) throws {
		let fileManager = FileManager.default
		try fileManager.createDirectoryIfNeeded(at: pendingImportStoreURL.deletingLastPathComponent())
		try fileManager.removeFileIfNeeded(at: pendingImportStoreURL)
		try fileManager.copyItem(at: url, to: pendingImportStoreURL)
	}

	/// Runs before the store is loaded, so no live objects point at the replaced store.
	private func _replaceStoreIfPending() {
		let defaults = UserDefaults.standard

		if FileManager.default.fileExists(atPath: Self.pendingImportStoreURL.path) {
			_replaceStore(with: Self.pendingImportStoreURL)
		} else if defaults.bool(forKey: Self.pendingFeatherPlusMigrationKey), Self.hasFeatherPlusData {
			defaults.removeObject(forKey: Self.pendingFeatherPlusMigrationKey)
			_replaceStore(with: Self.featherPlusStoreURL)
		}
	}

	private func _replaceStore(with source: URL) {
		guard let destination = container.persistentStoreDescriptions.first?.url else { return }
		defer { _removeStoreFiles(at: source) }

		do {
			try FileManager.default.createDirectoryIfNeeded(at: destination.deletingLastPathComponent())
			try container.persistentStoreCoordinator.replacePersistentStore(
				at: destination,
				destinationOptions: nil,
				withPersistentStoreFrom: source,
				sourceOptions: nil,
				ofType: NSSQLiteStoreType
			)
		} catch {
			print("Failed to replace database from \(source.lastPathComponent): \(error)")
		}
	}

	private func _removeStoreFiles(at url: URL) {
		let base = url.deletingPathExtension()
		for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
			try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
		}
	}
	
	var context: NSManagedObjectContext {
		container.viewContext
	}
	
	func saveContext() {
		DispatchQueue.main.async {
			if self.context.hasChanges {
				try? self.context.save()
			}
		}
	}
	
	func clearContext<T: NSManagedObject>(request: NSFetchRequest<T>) {
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
		_ = try? context.execute(deleteRequest)
	}
	
	func countContent<T: NSManagedObject>(for type: T.Type) -> String {
		let request = T.fetchRequest()
		return "\((try? context.count(for: request)) ?? 0)"
	}

	private func _loadPersistentStoreAggressively() {
		container.loadPersistentStores { description, error in
			if error != nil {
				self._destroyStore(at: description.url)
				self.container.loadPersistentStores { _, error in
					if let error {
						fatalError("Core Data unrecoverable: \(error)")
					}
				}
			}
		}
	}

	private func _destroyStore(at url: URL?) {
		guard let url else { return }

		let base = url.deletingPathExtension()
		let fm = FileManager.default

		let files = [
			base.appendingPathExtension("sqlite"),
			base.appendingPathExtension("sqlite-wal"),
			base.appendingPathExtension("sqlite-shm")
		]

		for file in files {
			try? fm.removeItem(at: file)
		}
		
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.signed)
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.unsigned)
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.certificates)
		UserDefaults.standard.set(0, forKey: "feather.selectedCert")
	}
}
