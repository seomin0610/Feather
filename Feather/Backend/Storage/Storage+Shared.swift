//
//  Storage+Shared.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData
import UIKit

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
	
	@MainActor private static var _isAskingToReplace = false

	/// Deletes older apps of the same kind sharing a bundle identifier, when "Replace Apps on Update" is enabled.
	@MainActor
	func deleteOutdatedApps(identifier: String?, version: String?, excluding uuid: String, signed: Bool) async {
		let defaults = UserDefaults.standard
		let replaceApps = defaults.object(forKey: "Feather.replaceAppsOnUpdate") as? Bool
		let replaceSameVersion = defaults.object(forKey: "Feather.replaceAppsOnUpdate.sameVersion") as? Bool ?? true
		let replaceSigned = defaults.object(forKey: "Feather.replaceAppsOnUpdate.signed") as? Bool ?? true

		guard
			replaceApps != false,
			!signed || replaceSigned,
			let identifier,
			!identifier.isEmpty
		else {
			return
		}

		var predicates = [NSPredicate(format: "identifier == %@ AND uuid != %@", identifier, uuid)]
		if !replaceSameVersion {
			predicates.append(NSPredicate(format: "NOT (version == %@)", version ?? NSNull()))
		}
		let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
		let apps: [AppInfoPresentable]

		if signed {
			let request: NSFetchRequest<Signed> = Signed.fetchRequest()
			request.predicate = predicate
			apps = (try? context.fetch(request)) ?? []
		} else {
			let request: NSFetchRequest<Imported> = Imported.fetchRequest()
			request.predicate = predicate
			apps = (try? context.fetch(request)) ?? []
		}

		guard !apps.isEmpty else { return }

		if replaceApps == nil {
			guard !Self._isAskingToReplace, let presenter = UIApplication.topViewController() else { return }
			Self._isAskingToReplace = true

			let shouldReplace = await withCheckedContinuation { continuation in
				UIAlertController.showAlert(
					presenter,
					title: .localized("Replace Older Versions?"),
					message: .localized("Older copies of this app will be deleted whenever a newer one is added. You can change this later in Archive & Compression settings."),
					actions: [
						UIAlertAction(title: .localized("Keep"), style: .cancel) { _ in continuation.resume(returning: false) },
						UIAlertAction(title: .localized("Replace"), style: .destructive) { _ in continuation.resume(returning: true) }
					]
				)
			}

			Self._isAskingToReplace = false
			defaults.set(shouldReplace, forKey: "Feather.replaceAppsOnUpdate")
			guard shouldReplace else { return }
		}

		apps.forEach(deleteApp(for:))
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
