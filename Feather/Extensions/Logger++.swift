//
//  Logger++.swift
//  Feather
//
//  Created by samara on 24.05.2025.
//

import OSLog
import UIKit

extension Logger {
	private static var subsystem = Bundle.main.bundleIdentifier!
	static let signing = Logger(subsystem: subsystem, category: "Signing")
	static let misc = Logger(subsystem: subsystem, category: "Misc")
	static let install = Logger(subsystem: subsystem, category: "Install")

	static func exportLogs() throws -> URL {
		let store = try OSLogStore(scope: .currentProcessIdentifier)
		let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions.insert(.withFractionalSeconds)

		var text = "\(Bundle.main.name) \(Bundle.main.version), iOS \(UIDevice.current.systemVersion)\n"
		for case let entry as OSLogEntryLog in entries {
			text += "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)\n"
		}

		let url = FileManager.default.temporaryDirectory.appendingPathComponent("Feather-\(Int(Date().timeIntervalSince1970)).log")
		try text.write(to: url, atomically: true, encoding: .utf8)
		return url
	}
}
