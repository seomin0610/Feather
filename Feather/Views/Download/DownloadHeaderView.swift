//
//  DownloadHeaderView.swift
//  Feather
//
//  Created by samara on 16.05.2025.
//

import SwiftUI
import Combine
import NimbleExtensions

struct DownloadHeaderView: View {
	@ObservedObject var downloadManager: DownloadManager
	
	var body: some View {
		ZStack {
			if !downloadManager.downloads.isEmpty {
				VStack {
					VStack(spacing: 12) {
						if let firstDownload = downloadManager.downloads.first {
							DownloadItemView(download: firstDownload)
							
							if downloadManager.downloads.count > 1 {
								HStack {
									Spacer()
									Text(verbatim: "+\(downloadManager.downloads.count - 1)")
										.font(.caption)
										.foregroundColor(.secondary)
										.padding(.vertical, 4)
								}
							}
						}
					}
					.padding(.horizontal)
				}
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(), value: downloadManager.downloads.count)
	}
}

struct DownloadItemView: View {
	let download: Download
	@State private var progress: Double = 0
	@State private var bytesDownloaded: Int64 = 0
	@State private var totalBytes: Int64 = 0
	@State private var unpackageProgress: Double = 0
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(download.fileName)
				.font(.subheadline)
				.lineLimit(1)
			
			ProgressView(value: _phaseProgress)
				.progressViewStyle(.linear)
			
			HStack {
				Text(verbatim: "\(_isExtracting ? String.localized("Extracting") : String.localized("Downloading")) \(Int(_phaseProgress * 100))%")
					.contentTransition(.numericText())
				Spacer()
				if !_isExtracting, totalBytes > 0 {
					Text(verbatim: "\($bytesDownloaded.wrappedValue.formattedByteCount) / \(totalBytes.formattedByteCount)")
						.contentTransition(.numericText())
				}
			}
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding(.vertical, 4)
		.onReceive(download.$progress) { self.progress = $0 }
		.onReceive(download.$bytesDownloaded) { self.bytesDownloaded = $0 }
		.onReceive(download.$totalBytes) { self.totalBytes = $0 }
		.onReceive(download.$unpackageProgress) { self.unpackageProgress = $0 }
	}
	
	private var _isExtracting: Bool {
		download.onlyArchiving || progress >= 1
	}
	
	private var _phaseProgress: Double {
		_isExtracting ? unpackageProgress : progress
	}
}
