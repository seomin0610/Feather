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

	@State private var _token: String = RemoteControlServer.token
	@State private var _isTokenVisible = false

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

				if let error = _server.lastError {
					Text(error)
						.font(.footnote)
						.foregroundStyle(.red)
				}
			} footer: {
				Text(.localized("Lets a computer import, sign, install and export apps over HTTP. Feather has to stay open for it to answer."))
			}

			NBSection(.localized("Token")) {
				Button {
					_isTokenVisible.toggle()
				} label: {
					Text(verbatim: _isTokenVisible ? _token : String(repeating: "•", count: 16))
						.font(.system(.footnote, design: .monospaced))
						.foregroundStyle(.primary)
				}

				Button(.localized("Copy Connection Command"), systemImage: "doc.on.doc") {
					UIPasteboard.general.string = """
					export FEATHER_HOST=\(_server.isRunning ? _server.address : "http://127.0.0.1:\(_port)")
					export FEATHER_TOKEN=\(_token)
					"""
				}

				Button(.localized("Regenerate Token"), systemImage: "arrow.clockwise") {
					_token = RemoteControlServer.regenerateToken()
					if _enabled { _server.restart() }
				}
			} footer: {
				Text(verbatim: .localized("Every request needs this token. Over USB, forward the port with iproxy %@ %@ and connect to http://127.0.0.1:%@", arguments: "\(_port)", "\(_port)", "\(_port)"))
			}
		}
		.onChange(of: _enabled) { _ in
			_server.applyStoredState()
		}
		.onDisappear {
			// port edits are applied on the way out, so typing one doesn't bounce the server per keystroke
			if _enabled, _server.isRunning, !_server.address.hasSuffix(":\(_port)") {
				_server.restart()
			}
		}
	}
}
