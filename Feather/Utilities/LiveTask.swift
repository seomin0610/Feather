//
//  LiveTask.swift
//  Feather
//

import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

// MARK: - Shim
enum LiveTask {
	#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
	/// Typed loosely so the dictionary can exist below iOS 16.2.
	private static var _activities: [String: Any] = [:]
	/// ActivityKit throttles anything chattier than a whole percent.
	private static var _sent: [String: (Int, String, Int)] = [:]
	private static var _finishing: Set<String> = []
	#endif

	static func start(_ id: String, title: String, subtitle: String, goal: String? = nil, stages: [String] = []) {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		DispatchQueue.main.async {
			BackgroundAudioManager.shared.start(_holder(id))

			guard
				#available(iOS 16.2, *),
				_activities[id] == nil,
				!_finishing.contains(id),
				ActivityAuthorizationInfo().areActivitiesEnabled
			else {
				return
			}

			// a job cut short by Feather being killed leaves its activity up for hours
			let running = Set(_activities.values.compactMap { ($0 as? Activity<TaskProgressAttributes>)?.id })
			for activity in Activity<TaskProgressAttributes>.activities where !running.contains(activity.id) {
				Task { await activity.end(nil, dismissalPolicy: .immediate) }
			}

			let attributes = TaskProgressAttributes(
				title: title,
				goal: goal,
				stages: stages,
				tint: UserDefaults.standard.string(forKey: "Feather.userTintColor")
			)
			let state = TaskProgressAttributes.ContentState(progress: 0, step: subtitle)
			_activities[id] = try? Activity.request(
				attributes: attributes,
				content: .init(state: state, staleDate: nil)
			)
			_sent[id] = (0, subtitle, 0)
		}
		#endif
	}

	/// A progress of 1 finishes the task, unless it's only the end of an earlier stage.
	static func update(_ id: String, progress: Double, subtitle: String? = nil, stage: Int? = nil) {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		DispatchQueue.main.async {
			guard !_finishing.contains(id) else { return }

			guard
				#available(iOS 16.2, *),
				let activity = _activities[id] as? Activity<TaskProgressAttributes>
			else {
				if progress >= 1, stage == nil { stop(id) }
				return
			}

			let lastStage = max(activity.attributes.stages.count - 1, 0)
			if progress >= 1, (stage ?? lastStage) >= lastStage {
				finish(id)
				return
			}

			let stage = stage ?? activity.content.state.stage
			let percent = Int(progress * 100)
			let step = subtitle ?? activity.content.state.step
			if let last = _sent[id], last == (percent, step, stage) { return }
			_sent[id] = (percent, step, stage)

			let state = TaskProgressAttributes.ContentState(progress: progress, step: step, stage: stage)
			Task { await activity.update(.init(state: state, staleDate: nil)) }
		}
		#endif
	}

	static func finish(_ id: String) {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		DispatchQueue.main.async {
			guard
				#available(iOS 16.2, *),
				!_finishing.contains(id),
				let activity = _activities[id] as? Activity<TaskProgressAttributes>
			else {
				stop(id)
				return
			}

			_finishing.insert(id)
			let state = TaskProgressAttributes.ContentState(
				progress: 1,
				step: activity.content.state.step,
				stage: max(activity.attributes.stages.count - 1, 0)
			)

			Task {
				await activity.update(.init(state: state, staleDate: nil))
				try? await Task.sleep(nanoseconds: 1_500_000_000)
				await MainActor.run {
					_finishing.remove(id)
					stop(id)
				}
			}
		}
		#endif
	}

	/// A job already showing its finished state is left to close on its own.
	static func stop(_ id: String) {
		#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		DispatchQueue.main.async {
			guard !_finishing.contains(id) else { return }
			BackgroundAudioManager.shared.stop(_holder(id))
			_sent[id] = nil

			guard
				#available(iOS 16.2, *),
				let activity = _activities.removeValue(forKey: id) as? Activity<TaskProgressAttributes>
			else {
				return
			}

			Task { await activity.end(nil, dismissalPolicy: .immediate) }
		}
		#endif
	}

	#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
	private static func _holder(_ id: String) -> String {
		"task.\(id)"
	}
	#endif
}
