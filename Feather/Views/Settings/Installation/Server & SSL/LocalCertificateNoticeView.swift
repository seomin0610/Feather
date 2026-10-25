//
//  LocalCertificateNoticeView.swift
//  Feather
//
//  Created by Jeongmin on 25.10.2026.
//

import SwiftUI
import NimbleExtensions

struct LocalCertificateNoticeView: View {
	@Environment(\.dismiss) private var _dismiss
	@Environment(\.scenePhase) private var _scenePhase
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _step = 0
	@State private var _isTrusted = false

	private static let _shownKey = "Feather.localCertificateNotice.shown"
	private let _stepCount = 5

	static func shouldPresent() -> Bool {
		!UserDefaults.standard.bool(forKey: _shownKey)
	}

	/// Background launches build the app too, so it only counts once it's on screen.
	private static func _markShown() {
		UserDefaults.standard.set(true, forKey: _shownKey)
	}

	static func resetShown() {
		UserDefaults.standard.removeObject(forKey: _shownKey)
	}

	var body: some View {
		VStack(spacing: 0) {
			_topBar()
				.padding(.horizontal, 16)
				.padding(.top, 8)

			TabView(selection: $_step) {
				_intro().tag(0)
				_download().tag(1)
				_install().tag(2)
				_trust().tag(3)
				_finish().tag(4)
			}
			.tabViewStyle(.page(indexDisplayMode: .never))
			.animation(.easeInOut(duration: 0.25), value: _step)
		}
		.background(Color(uiColor: .systemBackground).ignoresSafeArea())
		.task {
			if _scenePhase == .active { Self._markShown() }
			await _checkTrust()
		}
		.onChange(of: _scenePhase) { phase in
			if phase == .background { SettingsGuide.announce() }
			guard phase == .active else { return }
			Self._markShown()
			SettingsGuide.stop()
			Task { await _checkTrust() }
		}
		.onDisappear {
			SettingsGuide.stop()
		}
	}

	private func _openSettings(title: String, path: String, symbol: String) {
		SettingsGuide.start(title: title, path: path, symbol: symbol)
		// App-prefs: links from third-party apps land on Feather's own settings page,
		// so launch the Settings app itself instead.
		UIApplication.openApp(with: "com.apple.Preferences")
	}

	private func _checkTrust() async {
		let trusted = await Task.detached(priority: .userInitiated) {
			LocalCertificateAuthority.isTrusted()
		}.value
		withAnimation(.easeInOut) { _isTrusted = trusted }
	}

	private func _next() {
		_step = min(_step + 1, _stepCount - 1)
	}
}

extension LocalCertificateNoticeView {
	@ViewBuilder
	private func _intro() -> some View {
		_page(
			icon: { FRAppIconView(size: 96) },
			title: .localized("Installing Has Changed"),
			message: .localized("backloop.dev has shut down. To keep installing fully on this device, Feather now uses a certificate it makes itself."),
			content: {
				VStack(alignment: .leading, spacing: 18) {
					_feature("iphone", .localized("Made on this device"), .localized("It only works for Feather's own server on this device."))
					_feature("checkmark.shield", .localized("Set up once"), .localized("Install a profile and trust it. It stays trusted even if you reinstall Feather."))
					Divider()
						.padding(.leading, 48)
					_feature("globe", .localized("Or use Semi Local"), .localized("No certificate needed, but each install goes through an outside server."))
				}
				.padding(.top, 8)
			},
			actions: {
				_primary(.localized("Get Started"), action: _next)
				_secondary(.localized("Use Semi Local")) {
					_serverMethod = 1
					_dismiss()
				}
			}
		)
	}

	@ViewBuilder
	private func _download() -> some View {
		_page(
			icon: { _symbol("arrow.down.doc.fill") },
			title: .localized("Download the profile"),
			message: .localized("Safari opens and asks to download a configuration profile. Tap Allow."),
			content: {
				_tonal(.localized("Open in Safari"), systemImage: "safari") {
					try? LocalCertificateAuthority.openProfile()
				}
			},
			actions: {
				_primary(.localized("Continue"), action: _next)
			}
		)
	}

	@ViewBuilder
	private func _install() -> some View {
		_page(
			icon: { _symbol("gearshape.fill") },
			title: .localized("Install the profile"),
			message: .localized("In Settings, tap Profile Downloaded, or go to General › VPN & Device Management, then install \"Feather Local Certificate\"."),
			content: {
				_tonal(.localized("Open Settings"), systemImage: "gear") {
					_openSettings(
						title: .localized("Install the profile"),
						path: .localized("General › VPN & Device Management › Feather Local Certificate"),
						symbol: "arrow.down.doc.fill"
					)
				}
			},
			actions: {
				_primary(.localized("Continue"), action: _next)
			}
		)
	}

	@ViewBuilder
	private func _trust() -> some View {
		_page(
			icon: { _symbol(_isTrusted ? "checkmark.seal.fill" : "checkmark.shield.fill", tint: _isTrusted ? .green : .accentColor) },
			title: .localized("Turn on full trust"),
			message: .localized("Go to Settings › General › About › Certificate Trust Settings and turn on \"Feather Local CA\"."),
			content: {
				if !_isTrusted {
					_tonal(.localized("Open Settings"), systemImage: "gear") {
						_openSettings(
							title: .localized("Turn on full trust"),
							path: .localized("General › About › Certificate Trust Settings › Feather Local CA"),
							symbol: "checkmark.shield.fill"
						)
					}
				}

				Label(
					_isTrusted ? String.localized("Feather Local CA is trusted.") : String.localized("Come back here after turning it on."),
					systemImage: _isTrusted ? "checkmark.circle.fill" : "clock"
				)
				.font(.footnote)
				.foregroundStyle(_isTrusted ? Color.green : Color.secondary)
			},
			actions: {
				_primary(.localized("Continue"), isEnabled: _isTrusted, action: _next)
				if !_isTrusted {
					_secondary(.localized("Set Up Later"), action: _next)
				}
			}
		)
	}

	@ViewBuilder
	private func _finish() -> some View {
		_page(
			icon: { _symbol(_isTrusted ? "checkmark.seal.fill" : "clock.fill", tint: _isTrusted ? .green : .secondary) },
			title: _isTrusted ? .localized("All Set") : .localized("Set It Up Anytime"),
			message: _isTrusted
				? .localized("Apps now install fully on this device.")
				: .localized("Until then, Fully Local can't install apps. You can finish setup or switch to Semi Local in Settings › Installation."),
			content: { EmptyView() },
			actions: {
				_primary(.localized("Done")) { _dismiss() }
			}
		)
	}
}

extension LocalCertificateNoticeView {
	private func _page<Icon: View, Content: View, Actions: View>(
		@ViewBuilder icon: () -> Icon,
		title: String,
		message: String,
		@ViewBuilder content: () -> Content,
		@ViewBuilder actions: () -> Actions
	) -> some View {
		VStack(spacing: 24) {
			Spacer()

			icon()

			VStack(spacing: 8) {
				Text(title)
					.font(.system(size: 28, weight: .bold))
					.multilineTextAlignment(.center)

				Text(message)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(.horizontal, 32)

			VStack(spacing: 12) {
				content()
			}
			.frame(maxWidth: 420)
				.padding(.horizontal, 32)

			Spacer()

			VStack(spacing: 12) {
				actions()
			}
			.frame(maxWidth: 420)
			.padding(.horizontal, 24)
			.padding(.bottom, 16)
		}
	}

	@ViewBuilder
	private func _symbol(_ name: String, tint: Color = .accentColor) -> some View {
		let image = Image(systemName: name)
			.font(.system(size: 72))
			.foregroundStyle(tint)
			.frame(width: 96, height: 96)

		if #available(iOS 17.0, *) {
			image.contentTransition(.symbolEffect(.replace))
		} else {
			image
		}
	}

	private func _feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
		HStack(alignment: .top, spacing: 16) {
			Image(systemName: symbol)
				.font(.system(size: 22))
				.foregroundStyle(Color.accentColor)
				.frame(width: 32, height: 32)

			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.headline)
				Text(detail)
					.font(.footnote)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private func _primary(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.headline)
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 14)
				.background(isEnabled ? Color.accentColor : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
		.disabled(!isEnabled)
	}

	private func _secondary(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	private func _tonal(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Label(title, systemImage: systemImage)
				.font(.headline)
				.foregroundStyle(Color.accentColor)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 14)
				.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
	}

	private func _topBar() -> some View {
		ZStack {
			HStack(spacing: 6) {
				ForEach(0..<_stepCount, id: \.self) { index in
					Circle()
						.fill(index == _step ? Color.accentColor : Color.primary.opacity(0.18))
						.frame(width: 6, height: 6)
				}
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 8)
			.background(.ultraThinMaterial, in: Capsule())

			if _step > 0, _step < _stepCount - 1 {
				HStack {
					Button {
						_step -= 1
					} label: {
						Image(systemName: "chevron.left")
							.font(.system(size: 16, weight: .semibold))
							.frame(width: 32, height: 32)
					}
					Spacer()
				}
			}
		}
		.frame(height: 44)
	}
}
