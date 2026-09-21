//
//  RemoteView.swift
//  Feather
//
//  Created by Jeongmin on 20.09.2026.
//

import SwiftUI
import UIKit
import NimbleViews

// MARK: - View
struct RemoteView: View {
	@StateObject private var _server = RemoteControlServer.shared

	@AppStorage(RemoteControlServer.enabledKey) private var _enabled: Bool = false
	@AppStorage(RemoteControlServer.portKey) private var _port: Int = RemoteControlServer.defaultPort
	@AppStorage(RemoteControlServer.keepAliveKey) private var _keepAlive: Bool = true

	// MARK: Body
	var body: some View {
		NBList(.localized("Remote CLI")) {
			Section {
				Toggle(.localized("Enable Remote CLI"), systemImage: "terminal", isOn: $_enabled)

				LabeledContent(.localized("Status")) {
					Text(_server.isRunning ? _server.address : .localized("Stopped"))
						.foregroundStyle(_server.isRunning ? Color.green : Color.secondary)
				}

				LabeledContent(.localized("Port")) {
					TextField("", value: $_port, format: .number.grouping(.never))
						.keyboardType(.numberPad)
						.multilineTextAlignment(.trailing)
				}

				Toggle(.localized("Keep Running in Background"), systemImage: "moon.zzz", isOn: $_keepAlive)

				if let error = _server.lastError {
					Text(error)
						.font(.footnote)
						.foregroundStyle(.red)
				}
			} footer: {
				Text(.localized("Lets a paired computer import, sign, install and export apps over HTTP. Without the background option, Feather only answers while it is on screen. This always starts off when Feather launches."))
			}

			NBSection(.localized("Paired Computers")) {
				if _server.paired.isEmpty {
					Text(.localized("Nothing paired yet."))
						.font(.footnote)
						.foregroundColor(.disabled())
				} else {
					ForEach(_server.paired) { computer in
						VStack(alignment: .leading, spacing: 2) {
							Text(computer.name)
							Text(verbatim: "\(computer.address) · \(computer.date.formatted(date: .abbreviated, time: .shortened))")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
					}
					.onDelete { offsets in
						for computer in offsets.map({ _server.paired[$0] }) {
							_server.unpair(computer)
						}
					}
				}

				Button(.localized("Copy Pairing Command"), systemImage: "doc.on.doc") {
					UIPasteboard.general.string = "feather login \(_server.isRunning ? _server.address : "http://127.0.0.1:\(_port)")"
				}
			} footer: {
				Text(.localized("Run the pairing command on the computer. This device asks before anything is paired, and swiping a row away cuts that computer off."))
			}
		}
		.onChange(of: _enabled) { _ in
			_server.applyStoredState()
		}
		.onChange(of: _keepAlive) { _ in
			_server.applyKeepAlive()
		}
		.onDisappear {
			// port edits are applied on the way out, so typing one doesn't bounce the server per keystroke
			if _enabled, _server.isRunning, !_server.address.hasSuffix(":\(_port)") {
				_server.restart()
			}
		}
	}
}
