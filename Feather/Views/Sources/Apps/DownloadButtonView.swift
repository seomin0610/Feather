//
//  DownloadButtonView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import UIKit
import Combine
import AltSourceKit
import NimbleViews

struct DownloadButtonView: View {
	let sourceURL: URL?
	let source: ASRepository?
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared
	@ObservedObject private var updateManager = UpdateManager.shared

	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
	) private var _signedApps: FetchedResults<Signed>

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?

	/// Only a signed copy can have reached the home screen, an unsigned import never got installed.
	/// PPQ protection appends a suffix to the identifier, so those still count as the same app.
	private var _installed: Signed? {
		guard let sourceIdentifier = app.id else { return nil }

		return _signedApps.first {
			guard let identifier = $0.identifier else { return false }
			return identifier == sourceIdentifier || identifier.hasPrefix("\(sourceIdentifier).")
		}
	}

	private var _update: AppUpdate? {
		guard let sourceIdentifier = app.id else { return nil }
		return updateManager.updates.values.first { $0.bundleIdentifier == sourceIdentifier }
	}

	/// An update downloads under its own id, so both have to be watched.
	private var _download: Download? {
		downloadManager.getDownload(by: app.currentUniqueId)
			?? _update.flatMap { updateManager.download(for: $0) }
	}

	var body: some View {
		ZStack {
			if let currentDownload = _download {
				ZStack {
					Circle()
						.trim(from: 0, to: downloadProgress)
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.frame(width: 31, height: 31)
						.animation(.smooth, value: downloadProgress)

					Image(systemName: downloadProgress >= 0.75 ? "archivebox" : "square.fill")
						.foregroundStyle(.tint)
						.font(.footnote).bold()
				}
				.onTapGesture {
					if downloadProgress <= 0.75 {
						downloadManager.cancelDownload(currentDownload)
					}
				}
				.compatTransition()
			} else if let update = _update {
				_button(.localized("Update")) {
					updateManager.startUpdate(update)
				}
			} else if let installed = _installed, let identifier = installed.identifier {
				_button(.localized("Open")) {
					UIApplication.openApp(with: identifier)
				}
			} else {
				_button(.localized("Get")) {
					if let url = app.currentDownloadUrl {
						_ = downloadManager.startDownload(
							from: url,
							id: app.currentUniqueId,
							sourceProvenance: _sourceProvenance()
						)
					}
				}
			}
		}
		.onAppear(perform: setupObserver)
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			setupObserver()
		}
		.animation(.easeInOut(duration: 0.3), value: _download != nil)
	}

	@ViewBuilder
	private func _button(_ title: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.lineLimit(0)
				.font(.headline.bold())
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 24)
				.padding(.vertical, 6)
				.background(Color(uiColor: .quaternarySystemFill))
				.clipShape(Capsule())
		}
		.buttonStyle(.borderless)
		.compatTransition()
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download = _download else {
			downloadProgress = 0
			return
		}
		downloadProgress = download.overallProgress

		let publisher = Publishers.CombineLatest(
			download.$progress,
			download.$unpackageProgress
		)

		cancellable = publisher.sink { _, _ in
			downloadProgress = download.overallProgress
		}
	}

	private func _sourceProvenance() -> SourceAppProvenance? {
		guard let source else { return nil }
		return SourceAppProvenance(sourceURL: sourceURL, repository: source, app: app)
	}
}
