//
//  LibraryUpdateCellView.swift
//  Feather
//

import SwiftUI
import Combine
import NimbleViews

// MARK: - View
struct LibraryUpdateCellView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@ObservedObject private var downloadManager = DownloadManager.shared

	private let _title: String
	private let _localVersion: String?
	private let _remoteVersion: String
	private let _versionDate: Date?
	private let _size: Int64?
	private let _notes: String?
	private let _app: AppInfoPresentable?
	private let _download: () -> Download?
	private let _startUpdate: () -> Void

	init(update: AppUpdate, app: AppInfoPresentable?) {
		_title = update.appName
		_localVersion = update.localVersion
		_remoteVersion = update.remoteVersion
		_versionDate = update.versionDate
		_size = update.size
		_notes = update.releaseNotes
		_app = app
		_download = { UpdateManager.shared.download(for: update) }
		_startUpdate = { UpdateManager.shared.startUpdate(update) }
	}

	/// Feather's own update; app is nil so the icon falls back to Feather's.
	init(featherUpdate update: FeatherUpdate) {
		_title = Bundle.main.name
		_localVersion = update.localVersion
		_remoteVersion = update.remoteVersion
		_versionDate = update.versionDate
		_size = update.size
		_notes = update.releaseNotes
		_app = nil
		_download = { UpdateManager.shared.download(for: update) }
		_startUpdate = { UpdateManager.shared.startFeatherUpdate(update) }
	}

	// MARK: Body
	var body: some View {
		let isRegular = horizontalSizeClass != .compact

		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 18) {
				FRAppIconView(app: _app, size: 57)

				VStack(alignment: .leading, spacing: 2) {
					Text(_title)
						.font(.headline)
						.foregroundColor(.primary)
						.lineLimit(1)

					Text(verbatim: "\(_localVersion ?? .localized("Unknown")) → \(_remoteVersion)")
						.font(.subheadline)
						.foregroundColor(.secondary)
						.lineLimit(1)
						.minimumScaleFactor(0.8)

					if let details = _details {
						Text(verbatim: details)
							.font(.caption)
							.foregroundColor(.secondary)
							.lineLimit(1)
					}
				}
				.padding(.vertical, 2)
				.frame(maxWidth: .infinity, alignment: .leading)

				_updateButton
			}

			if let notes = _releaseNotes {
				ExpandableText(text: notes, lineLimit: 3)
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
		.padding(isRegular ? 12 : 0)
		.background(
			isRegular
				? RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(Color(.quaternarySystemFill))
				: nil
		)
		.animation(.easeInOut(duration: 0.3), value: _download() != nil)
	}

	private var _details: String? {
		var parts: [String] = []
		if let date = _versionDate {
			parts.append(date.formatted(date: .abbreviated, time: .omitted))
		}
		if let size = _size, size > 0 {
			parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
		}
		return parts.isEmpty ? nil : parts.joined(separator: " • ")
	}

	private var _releaseNotes: String? {
		guard
			let notes = _notes?.trimmingCharacters(in: .whitespacesAndNewlines),
			!notes.isEmpty
		else {
			return nil
		}
		return notes
	}
}

// MARK: - Extension: View
extension LibraryUpdateCellView {
	@ViewBuilder
	private var _updateButton: some View {
		if let download = _download() {
			UpdateDownloadProgressView(download: download)
				.compatTransition()
		} else {
			Button {
				_startUpdate()
			} label: {
				FRExpirationPillView(
					title: .localized("Update"),
					revoked: false,
					expiration: nil
				)
			}
			.buttonStyle(.borderless)
			.compatTransition()
		}
	}
}

// MARK: - Progress
/// Progress ring for an update download; tapping cancels before unpacking starts.
struct UpdateDownloadProgressView: View {
	let download: Download

	@State private var _progress: Double = 0
	@State private var _cancellable: AnyCancellable?

	var body: some View {
		ZStack {
			Circle()
				.trim(from: 0, to: _progress)
				.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
				.rotationEffect(.degrees(-90))
				.frame(width: 31, height: 31)
				.animation(.smooth, value: _progress)

			Image(systemName: _progress >= 0.75 ? "archivebox" : "square.fill")
				.foregroundStyle(.tint)
				.font(.footnote).bold()
		}
		.onTapGesture {
			if _progress <= 0.75 {
				DownloadManager.shared.cancelDownload(download)
			}
		}
		.onAppear(perform: _setupObserver)
		.onDisappear { _cancellable?.cancel() }
		.onChange(of: download.id) { _ in
			_setupObserver()
		}
	}

	private func _setupObserver() {
		_progress = download.overallProgress
		_cancellable = Publishers.CombineLatest(
			download.$progress,
			download.$unpackageProgress
		)
		.sink { [download] _, _ in
			_progress = download.overallProgress
		}
	}
}
