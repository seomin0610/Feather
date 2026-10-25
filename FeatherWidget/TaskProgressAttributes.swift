//
//  TaskProgressAttributes.swift
//  Feather
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

struct TaskProgressAttributes: ActivityAttributes {
	struct ContentState: Codable, Hashable {
		/// 0 to 1, within the current stage when there are stages.
		var progress: Double
		var step: String
		var stage: Int = 0
	}

	var title: String
	var goal: String?
	var stages: [String] = []
	/// The app's tint as a hex string, the widget can't read the app's user defaults.
	var tint: String?
}
#endif
