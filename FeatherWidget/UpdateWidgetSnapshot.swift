//
//  UpdateWidgetSnapshot.swift
//  Feather
//

import Foundation
import Security
import WidgetKit

// keychain instead of an app group, sideloading profiles rarely grant app groups
// but signing gives the app and its extensions the same keychain-access-groups
struct UpdateWidgetSnapshot: Codable {
	struct App: Codable {
		var name: String
		var icon: Data?
	}

	var apps: [App]
	var checkedAt: Date

	private static let _query: [String: Any] = [
		kSecClass as String: kSecClassGenericPassword,
		kSecAttrService as String: "Feather.UpdateWidget",
		kSecAttrAccount as String: "snapshot"
	]

	static func load() -> UpdateWidgetSnapshot? {
		var query = _query
		query[kSecReturnData as String] = true

		var result: AnyObject?
		guard
			SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
			let data = result as? Data
		else {
			return nil
		}

		return try? JSONDecoder().decode(UpdateWidgetSnapshot.self, from: data)
	}

	func save() {
		guard let data = try? JSONEncoder().encode(self) else { return }

		SecItemDelete(Self._query as CFDictionary)

		var item = Self._query
		item[kSecValueData as String] = data
		item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
		SecItemAdd(item as CFDictionary, nil)

		WidgetCenter.shared.reloadAllTimelines()
	}
}
