//
//  BackgroundTaskManager.swift
//  Feather
//
//  Created by Nagata Asami on 4/1/26.
//

#if !targetEnvironment(macCatalyst)

import Foundation
import BackgroundTasks
import CryptoKit

@available(iOS 26.0, *)
class BackgroundTaskManager: ObservableObject {
	static let shared = BackgroundTaskManager()
	
	private let baseId = "\(Bundle.main.bundleIdentifier!).userTask"
	
	private var activeTasks: [String: BGContinuedProcessingTask] = [:]
	private var registeredTasks: Set<String> = []
	/// Work that finished before the scheduler got around to launching its task.
	private var finishedTasks: Set<String> = []
	
	func startTask(for downloadId: String, filename: String, subtitle: String = .localized("Downloading")) {
		let taskIdentifier = "\(baseId).\(downloadId.md5)"
		finishedTasks.remove(taskIdentifier)
		
		if !registeredTasks.contains(taskIdentifier) {
			BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
				guard let task = task as? BGContinuedProcessingTask else { return }
				self.activeTasks[task.identifier] = task
				
				// short work can be over before this runs, don't leave it spinning
				if self.finishedTasks.remove(task.identifier) != nil {
					self.stopTask(identifier: task.identifier, success: true)
					return
				}
				
				task.expirationHandler = {
					if let download = DownloadManager.shared.getDownload(by: downloadId) {
						DownloadManager.shared.cancelDownload(download)
					}
					self.activeTasks.removeValue(forKey: task.identifier)
				}
			}
			self.registeredTasks.insert(taskIdentifier)
		}
		
		let request = BGContinuedProcessingTaskRequest(identifier: taskIdentifier, title: filename, subtitle: subtitle)
		request.strategy = .queue
		do {
			try BGTaskScheduler.shared.submit(request)
		} catch {
			print(error)
		}
	}
	
	func updateProgress(for downloadId: String, progress: Double, subtitle: String? = nil) {
		let taskIdentifier = "\(baseId).\(downloadId.md5)"
		
		guard let task = activeTasks[taskIdentifier] else {
			if progress >= 1.0 { finishedTasks.insert(taskIdentifier) }
			return
		}
		
		task.progress.totalUnitCount = 100
		task.progress.completedUnitCount = Int64(progress * 100)
		
		let percentage = "\(Int(progress * 100))%"
		task.updateTitle(task.title, subtitle: subtitle.map { "\($0) \(percentage)" } ?? percentage)
		
		if task.progress.completedUnitCount >= task.progress.totalUnitCount {
			stopTask(identifier: taskIdentifier, success: true)
		}
	}
	
	func stopTask(for downloadId: String, success: Bool) {
		stopTask(identifier: "\(baseId).\(downloadId.md5)", success: success)
	}
	
	private func stopTask(identifier: String, success: Bool) {
		guard let task = activeTasks[identifier] else {
			finishedTasks.insert(identifier)
			return
		}
		
		task.setTaskCompleted(success: success)
		activeTasks.removeValue(forKey: identifier)
	}
}

extension String {
	var md5: String {
		Insecure.MD5.hash(data: Data(self.utf8)).map { String(format: "%02hhx", $0) }.joined()
	}
}

#endif

// MARK: - Shim
/// Feeds the Dynamic Island where the API exists, does nothing where it doesn't,
/// so callers don't repeat the availability dance. Every touch is on the main
/// thread, the task bookkeeping is a plain dictionary.
enum LiveTask {
	static func start(_ id: String, title: String, subtitle: String) {
		#if !targetEnvironment(macCatalyst)
		guard #available(iOS 26.0, *) else { return }
		DispatchQueue.main.async {
			BackgroundTaskManager.shared.startTask(for: id, filename: title, subtitle: subtitle)
		}
		#endif
	}
	
	/// A progress of 1 finishes the task.
	static func update(_ id: String, progress: Double, subtitle: String? = nil) {
		#if !targetEnvironment(macCatalyst)
		guard #available(iOS 26.0, *) else { return }
		DispatchQueue.main.async {
			BackgroundTaskManager.shared.updateProgress(for: id, progress: progress, subtitle: subtitle)
		}
		#endif
	}
	
	static func stop(_ id: String, success: Bool = true) {
		#if !targetEnvironment(macCatalyst)
		guard #available(iOS 26.0, *) else { return }
		DispatchQueue.main.async {
			BackgroundTaskManager.shared.stopTask(for: id, success: success)
		}
		#endif
	}
}
