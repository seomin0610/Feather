//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct ServerView: View {
	@Environment(\.scenePhase) private var _scenePhase
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isCertificateTrusted: Bool?
	private let _serverMethods: [String] = [.localized("Fully Local"), .localized("Semi Local")]

	// MARK: Body
	var body: some View {
		Group {
			Section {
				Picker(.localized("Server Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.description) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}

			if _serverMethod == 0 {
				Section {
					LabeledContent {
						if let trusted = _isCertificateTrusted {
							Text(trusted ? .localized("Trusted") : .localized("Not Trusted"))
								.foregroundStyle(trusted ? .green : .secondary)
						} else {
							ProgressView()
						}
					} label: {
						Label(.localized("Local Certificate"), systemImage: "checkmark.shield")
					}

					Button(.localized("Install Certificate Profile"), systemImage: "arrow.down.doc") {
						do {
							try LocalCertificateAuthority.openProfile()
						} catch {
							UIAlertController.showAlertWithOk(
								title: .localized("Local Certificate"),
								message: error.localizedDescription
							)
						}
					}
				} footer: {
					Text(.localized("Fully local installs need Feather's own certificate, which only works for this device's local server. Install the profile, then turn on full trust for \"Feather Local CA\" in Settings > General > About > Certificate Trust Settings. Until then, Feather installs with Semi Local."))
				}
			}
		}
		.task(id: _serverMethod) {
			await _checkTrust()
		}
		.onChange(of: _scenePhase) { phase in
			guard phase == .active else { return }
			Task { await _checkTrust() }
		}
	}

	private func _checkTrust() async {
		guard _serverMethod == 0 else { return }
		_isCertificateTrusted = await Task.detached(priority: .userInitiated) {
			LocalCertificateAuthority.isTrusted()
		}.value
	}
}
