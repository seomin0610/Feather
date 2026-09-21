//
//  Storage+Shared.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData

// MARK: - Class extension: Apps (Shared)
extension Storage {
	func getUuidDirectory(for app: AppInfoPresentable) -> URL? {
		guard let uuid = app.uuid else { return nil }
		return app.isSigned
			? FileManager.default.signed(uuid)
			: FileManager.default.unsigned(uuid)
	}
	
	func getAppDirectory(for app: AppInfoPresentable) -> URL? {
		guard let url = getUuidDirectory(for: app) else { return nil }
		return FileManager.default.getPath(in: url, for: "app")
	}
	
	func deleteApp(for app: AppInfoPresentable) {
		let uuid = app.uuid
		Task { @MainActor in
			UpdateManager.shared.removeUpdate(for: uuid)
		}

		do {
			if let url = getUuidDirectory(for: app) {
				try? FileManager.default.removeItem(at: url)
			}
			deleteSourceMetadata(for: app.uuid)
			if let object = app as? NSManagedObject {
				context.delete(object)
			}
			saveContext()
		}
	}
	
	/// Deletes older apps of the same kind sharing a bundle identifier, when "Replace Apps on Update" is enabled.
	func deleteOutdatedApps(identifier: String?, version: String?, excluding uuid: String, signed: Bool) {
		let defaults = UserDefaults.standard
		let replaceSameVersion = defaults.object(forKey: "Feather.replaceAppsOnUpdate.sameVersion") as? Bool ?? true
		let replaceSigned = defaults.object(forKey: "Feather.replaceAppsOnUpdate.signed") as? Bool ?? true

		guard
			defaults.bool(forKey: "Feather.replaceAppsOnUpdate"),
			!signed || replaceSigned,
			let identifier,
			!identifier.isEmpty
		else {
			return
		}

		context.perform {
			var predicates = [NSPredicate(format: "identifier == %@ AND uuid != %@", identifier, uuid)]
			if !replaceSameVersion {
				predicates.append(NSPredicate(format: "NOT (version == %@)", version ?? NSNull()))
			}
			let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
			let apps: [AppInfoPresentable]

			if signed {
				let request: NSFetchRequest<Signed> = Signed.fetchRequest()
				request.predicate = predicate
				apps = (try? self.context.fetch(request)) ?? []
			} else {
				let request: NSFetchRequest<Imported> = Imported.fetchRequest()
				request.predicate = predicate
				apps = (try? self.context.fetch(request)) ?? []
			}

			for app in apps {
				self.deleteApp(for: app)
			}
		}
	}

	func getCertificate(from app: AppInfoPresentable) -> CertificatePair? {
		if let signed = app as? Signed {
			return signed.certificate
		}
		return nil
	}
}

// MARK: - Helpers
struct AnyApp: Identifiable {
	let base: AppInfoPresentable
	var archive: Bool = false
	var signAndInstall: Bool = false
	var remoteSigning: Bool = false

	var id: String {
		base.uuid ?? UUID().uuidString
	}
}

protocol AppInfoPresentable {
	var name: String? { get }
	var version: String? { get }
	var identifier: String? { get }
	var date: Date? { get }
	var icon: String? { get }
	var uuid: String? { get }
	var source: URL? { get }
	var isSigned: Bool { get }
	
}

extension Signed: AppInfoPresentable {
	var isSigned: Bool { true }
}

extension Imported: AppInfoPresentable {
	var isSigned: Bool { false }
}
