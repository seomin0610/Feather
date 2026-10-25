//
//  SettingsGuide.swift
//  Feather
//

import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

enum SettingsGuide {
	/// - Parameter path: Screens separated by " › ".
	static func start(title: String, path: String, symbol: String) {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }

		let attributes = SettingsGuideAttributes(
			title: title,
			stops: path.components(separatedBy: " › "),
			symbol: symbol,
			tint: UserDefaults.standard.string(forKey: "Feather.userTintColor")
		)

		let previous = Activity<SettingsGuideAttributes>.activities
		// request right away, iOS refuses once Feather has gone to the background
		_ = try? Activity.request(
			attributes: attributes,
			content: .init(state: .init(), staleDate: nil)
		)
		Task {
			for activity in previous {
				await activity.end(nil, dismissalPolicy: .immediate)
			}
		}
		#endif
	}

	/// An alert update is the only way to expand the island without a long press, and only for a few seconds.
	static func announce() {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		guard #available(iOS 16.2, *) else { return }
		for activity in Activity<SettingsGuideAttributes>.activities {
			let alert = AlertConfiguration(
				title: LocalizedStringResource(stringLiteral: activity.attributes.title),
				body: LocalizedStringResource(stringLiteral: activity.attributes.stops.joined(separator: " › ")),
				sound: .default
			)
			Task {
				await activity.update(.init(state: .init(), staleDate: nil), alertConfiguration: alert)
			}
		}
		#endif
	}

	static func stop() {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		guard #available(iOS 16.2, *) else { return }
		Task { await _endAll() }
		#endif
	}

	#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
	@available(iOS 16.2, *)
	private static func _endAll() async {
		for activity in Activity<SettingsGuideAttributes>.activities {
			await activity.end(nil, dismissalPolicy: .immediate)
		}
	}
	#endif
}
