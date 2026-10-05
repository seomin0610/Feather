//
//  BackgroundAudioManager.swift
//  Feather
//
//  Created by Nagata Asami on 12/10/25.
//

#if !targetEnvironment(macCatalyst)

import AVFoundation

class BackgroundAudioManager {
	static let shared = BackgroundAudioManager()
	private let _engine = AVAudioEngine()
	private let _lock = NSLock()
	private var _holders: Set<String> = []

	private init() {
		let silence = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
			let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
			for buffer in ablPointer {
				memset(buffer.mData, 0, Int(buffer.mDataByteSize))
			}
			return noErr
		}

		_engine.attach(silence)
		_engine.connect(silence, to: _engine.mainMixerNode, format: nil)

		// a call or a route change stops the engine, and nothing else would start it again
		NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: nil,
			queue: nil
		) { [weak self] note in
			let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
			if raw.flatMap(AVAudioSession.InterruptionType.init) == .ended {
				self?._resume()
			}
		}

		NotificationCenter.default.addObserver(
			forName: .AVAudioEngineConfigurationChange,
			object: _engine,
			queue: nil
		) { [weak self] _ in
			self?._resume()
		}
	}

	/// Keeps playing until every holder has called stop.
	func start(_ holder: String) {
		_lock.lock()
		defer { _lock.unlock() }

		_holders.insert(holder)
		_run()
	}

	func stop(_ holder: String) {
		_lock.lock()
		defer { _lock.unlock() }

		_holders.remove(holder)
		guard _holders.isEmpty else { return }

		_engine.stop()
		try? AVAudioSession.sharedInstance().setActive(false)
	}

	private func _resume() {
		_lock.lock()
		defer { _lock.unlock() }

		guard !_holders.isEmpty else { return }
		_run()
	}

	private func _run() {
		guard !_engine.isRunning else { return }

		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, options: [.mixWithOthers])
			try session.setActive(true)
			try _engine.start()
		} catch {
			print("failed to start engine:", error)
		}
	}
}

#endif
