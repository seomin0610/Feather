//
//  ArchiveHandler.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import Foundation
import UIKit.UIApplication
import Zip
import Zsign
import SwiftUI
import IDeviceSwift

final class ArchiveHandler: NSObject {
	@ObservedObject var viewModel: InstallerStatusViewModel
	
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	private var _appUrl: URL?
	
	private var _app: AppInfoPresentable
	private let _uniqueWorkDir: URL
	
	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) {
		self.viewModel = viewModel
		self._app = app
		self._uniqueWorkDir = _fileManager.temporaryDirectory
			.appendingPathComponent("FeatherInstall_\(_uuid)", isDirectory: true)
		
		super.init()
	}
	
	func move() async throws {
		guard let appUrl = Storage.shared.getAppDirectory(for: _app) else {
			throw SigningFileHandlerError.appNotFound
		}
		
		try _fileManager.createDirectoryIfNeeded(at: _uniqueWorkDir)
		_appUrl = appUrl
	}
	
	func archive(compression: ZipCompression? = nil) async throws -> URL {
		let compression = compression ?? ArchiveHandler.compression
		return try await Task.detached(priority: .userInitiated) { [self] in
			guard let appUrl = await self._appUrl else {
				throw SigningFileHandlerError.appNotFound
			}
			
			let zipUrl = self._uniqueWorkDir.appendingPathComponent("Archive.zip")
			let ipaUrl = self._uniqueWorkDir.appendingPathComponent("Archive.ipa")
			let progress: (Double) -> Void = { progress in
				Task { @MainActor in
					self.viewModel.packageProgress = progress
				}
			}
			
			if compression == .NoCompression {
				guard Zsign.archive(
					folder: appUrl.path,
					to: zipUrl.path,
					prefix: "Payload/\(appUrl.lastPathComponent)/",
					progress: progress
				) else {
					throw ZipError.zipFail
				}
			} else {
				let payloadUrl = self._uniqueWorkDir.appendingPathComponent("Payload")
				try FileManager.default.createDirectoryIfNeeded(at: payloadUrl)
				try FileManager.default.copyItem(at: appUrl, to: payloadUrl.appendingPathComponent(appUrl.lastPathComponent))
				
				try await Zip.zipFiles(
					paths: [payloadUrl],
					zipFilePath: zipUrl,
					password: nil,
					compression: compression,
					progress: progress
				)
			}
			
			try FileManager.default.moveItem(at: zipUrl, to: ipaUrl)
			return ipaUrl
		}.value
	}
	
	func moveToArchive(_ package: URL, shouldOpen: Bool = false) async throws -> URL? {
		let appendingString = "\(_app.name!)_\(_app.version!)_\(Int(Date().timeIntervalSince1970)).ipa"
		let dest = _fileManager.archives.appendingPathComponent(appendingString)
		
		try? _fileManager.moveItem(
			at: package,
			to: dest
		)
		
		if shouldOpen {
			await MainActor.run {
				UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
			}
		}
		
		return dest
	}
	
	func clean() async throws {
		try _fileManager.removeFileIfNeeded(at: _uniqueWorkDir)
	}
	
	static var compression: ZipCompression {
		let level = UserDefaults.standard.object(forKey: "Feather.compressionLevel") as? Int
		return level.flatMap(ZipCompression.init(rawValue:)) ?? .NoCompression
	}
}
