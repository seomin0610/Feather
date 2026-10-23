//
//  VerificationWarningView.swift
//  Feather
//

import SwiftUI

// MARK: - Model
struct VerificationIssue: Identifiable {
	enum Kind {
		case bundleID
		case hash
		case version
		case buildVersion
		case minimumOS
	}

	let kind: Kind
	var expected: String? = nil
	var actual: String? = nil

	var id: Kind { kind }
}

// MARK: - View
struct VerificationWarningView: View {
	let appName: String
	let appIcon: UIImage?
	let sourceName: String?
	let issues: [VerificationIssue]
	var onHeightChange: ((CGFloat) -> Void)? = nil
	let onDecision: (Bool) -> Void

	@State private var _contentHeight: CGFloat = 0
	@State private var _buttonsHeight: CGFloat = 0

	private var _hasTampering: Bool {
		issues.contains { $0.kind == .hash }
	}

	private var _isSecurityWarning: Bool {
		issues.contains { $0.kind != .minimumOS }
	}

	private var _tint: Color {
		_hasTampering ? .red : .orange
	}

	// MARK: Body
	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				_header()
				_issueList()

				if sourceName != nil, _isSecurityWarning {
					Text(.localized("Only add it if you trust this source."))
						.font(.footnote)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 4)
				}
			}
			.padding(.horizontal, 20)
			.padding(.top, 28)
			.padding(.bottom, 12)
			.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _contentHeight = $0 }
		}
		.safeAreaInset(edge: .bottom) {
			_buttons()
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _buttonsHeight = $0 }
		}
		.onChange(of: _contentHeight + _buttonsHeight) { height in
			onHeightChange?(height)
		}
	}
}

// MARK: - Extension: View
extension VerificationWarningView {
	@ViewBuilder
	private func _header() -> some View {
		HStack(alignment: .center, spacing: 16) {
			Group {
				if let appIcon {
					Image(uiImage: appIcon).appIconStyle(size: 72)
				} else {
					Image("App_Unknown").appIconStyle(size: 72)
				}
			}

			VStack(alignment: .leading, spacing: 6) {
				Label(
					_isSecurityWarning ? .localized("Security Warning") : .localized("Compatibility Warning"),
					systemImage: _isSecurityWarning ? "exclamationmark.shield.fill" : "iphone.slash"
				)
				.font(.footnote.weight(.semibold))
				.foregroundStyle(_tint)
				.padding(.horizontal, 9)
				.padding(.vertical, 4)
				.background(Capsule().fill(_tint.opacity(0.15)))

				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: appName)
						.font(.title3.weight(.bold))
						.lineLimit(2)

					if let sourceName {
						Text(verbatim: .localized("Downloaded from %@", arguments: sourceName))
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
			}

			Spacer(minLength: 0)
		}
	}

	@ViewBuilder
	private func _issueList() -> some View {
		VStack(spacing: 0) {
			ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
				if index > 0 {
					Divider().padding(.leading, 54)
				}
				_issueRow(issue)
			}
		}
		.background(
			Color(uiColor: .tertiarySystemFill),
			in: RoundedRectangle(cornerRadius: 20, style: .continuous)
		)
	}

	@ViewBuilder
	private func _issueRow(_ issue: VerificationIssue) -> some View {
		let (symbol, title, note, labels) = _content(for: issue)

		HStack(alignment: .firstTextBaseline, spacing: 14) {
			Image(systemName: symbol)
				.font(.body.weight(.semibold))
				.foregroundStyle(issue.kind == .hash ? .red : .orange)
				.frame(width: 24)

			VStack(alignment: .leading, spacing: 6) {
				Text(title)
					.font(.body.weight(.semibold))

				if let note {
					Text(note)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				if let labels, let expected = issue.expected, let actual = issue.actual {
					Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
						GridRow {
							Text(labels.expected).foregroundStyle(.secondary)
							Text(verbatim: expected)
						}
						GridRow {
							Text(labels.actual).foregroundStyle(.secondary)
							Text(verbatim: actual)
						}
					}
					.font(.subheadline)
					.textSelection(.enabled)
				}
			}

			Spacer(minLength: 0)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
	}

	@ViewBuilder
	private func _buttons() -> some View {
		VStack(spacing: 6) {
			Button {
				onDecision(false)
			} label: {
				Text(.localized("Cancel"))
					.font(.headline)
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)

			Button(role: .destructive) {
				onDecision(true)
			} label: {
				Text(.localized("Add Anyway"))
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderless)
			.controlSize(.large)
		}
		.padding(.horizontal, 20)
		.padding(.top, 12)
		.padding(.bottom, 8)
		.background(.bar)
	}

	private func _content(
		for issue: VerificationIssue
	) -> (symbol: String, title: String, note: String?, labels: (expected: String, actual: String)?) {
		let sourceVsApp = (expected: String.localized("Source"), actual: String.localized("App"))

		switch issue.kind {
		case .bundleID:
			return ("shippingbox", .localized("Bundle ID doesn't match"), .localized("This isn't the app the source describes. It may be a fake that only copies the name and icon."), sourceVsApp)
		case .hash:
			return ("number", .localized("File hash doesn't match"), .localized("This isn't the file the source published. It may have changed during download, or someone may have added malicious code."), nil)
		case .version:
			return ("tag", .localized("Version doesn't match"), .localized("A different version than the source lists was downloaded. The source may be poorly maintained, or the file may have been swapped."), sourceVsApp)
		case .buildVersion:
			return ("hammer", .localized("Build version doesn't match"), .localized("The version number matches, but it's a different build. The file may have been swapped."), sourceVsApp)
		case .minimumOS:
			return ("iphone", .localized("May not run on this device"), nil, (.localized("Required"), .localized("This Device")))
		}
	}
}

// MARK: - Presenting
extension VerificationWarningView {
	@MainActor
	static func present(
		on presenter: UIViewController,
		appName: String,
		appIcon: UIImage?,
		sourceName: String?,
		issues: [VerificationIssue]
	) async -> Bool {
		await withCheckedContinuation { continuation in
			var hasDecided = false
			let decide: (Bool) -> Void = { shouldAdd in
				guard !hasDecided else { return }
				hasDecided = true
				continuation.resume(returning: shouldAdd)
			}

			var controller: UIViewController?
			var fittingHeight: CGFloat = 480
			let view = VerificationWarningView(
				appName: appName,
				appIcon: appIcon,
				sourceName: sourceName,
				issues: issues,
				onHeightChange: { height in
					guard height > 0, let sheet = controller?.sheetPresentationController else { return }
					fittingHeight = height
					sheet.animateChanges { sheet.invalidateDetents() }
				}
			) { shouldAdd in
				decide(shouldAdd)
				controller?.dismiss(animated: true)
			}
			.onDisappear { decide(false) }

			let hosting = UIHostingController(rootView: view)
			controller = hosting
			hosting.sheetPresentationController?.detents = [
				.custom(identifier: .init("fit")) { context in
					min(fittingHeight, context.maximumDetentValue)
				}
			]

			UINotificationFeedbackGenerator().notificationOccurred(.warning)
			presenter.present(hosting, animated: true)
		}
	}
}
