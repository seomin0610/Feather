//
//  SettingsGuideAttributes.swift
//  Feather
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

struct SettingsGuideAttributes: ActivityAttributes {
	struct ContentState: Codable, Hashable {}

	var title: String
	var stops: [String]
	var symbol: String
	/// The app's tint as a hex string, the widget can't read the app's user defaults.
	var tint: String?
}
#endif
