//
//  ArchiveView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import Zip
import NimbleViews

// MARK: - View
struct ArchiveView: View {
	@AppStorage("Feather.compressionLevel") private var _compressionLevel: Int = ZipCompression.DefaultCompression.rawValue
	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.replaceAppsOnUpdate") private var _replaceAppsOnUpdate: Bool = false
	@AppStorage("Feather.replaceAppsOnUpdate.sameVersion") private var _replaceSameVersion: Bool = true
	@AppStorage("Feather.replaceAppsOnUpdate.signed") private var _replaceSigned: Bool = true
	@AppStorage(UpdateManager.deleteAfterSelfUpdateKey) private var _deleteAfterSelfUpdate: Bool = false
	@AppStorage("Feather.verification.security") private var _showSecurityWarnings: Bool = true
	@AppStorage("Feather.verification.compatibility") private var _showCompatibilityWarnings: Bool = true
	
	// MARK: Body
	var body: some View {
		NBList(.localized("Archive & Compression")) {
			Section {
				Picker(.localized("Compression Level"), systemImage: "archivebox", selection: $_compressionLevel) {
					ForEach(ZipCompression.allCases, id: \.rawValue) { level in
						Text(level.label).tag(level.rawValue)
					}
				}
			}
			
			Section {
				Toggle(.localized("Show Sheet when Exporting"), systemImage: "square.and.arrow.up", isOn: $_useShareSheet)
			} footer: {
				Text(.localized("Toggling show sheet will present a share sheet after exporting to your files."))
			}

			Section {
				Toggle(.localized("Replace Apps on Update"), systemImage: "arrow.triangle.2.circlepath", isOn: $_replaceAppsOnUpdate)

				if _replaceAppsOnUpdate {
					Toggle(.localized("Replace Same Version"), systemImage: "equal.circle", isOn: $_replaceSameVersion)
					Toggle(.localized("Replace Signed Apps"), systemImage: "signature", isOn: $_replaceSigned)
				}
			} footer: {
				Text(.localized("When a new version of an app is added to your library, older copies with the same bundle identifier will be deleted."))
			}

			Section {
				Toggle(.localized("Delete Feather After Updating"), systemImage: "trash", isOn: $_deleteAfterSelfUpdate)
			} footer: {
				Text(.localized("After Feather updates itself, its copies in your library will be deleted."))
			}

			Section {
				Toggle(.localized("Show Security Warnings"), systemImage: "exclamationmark.shield", isOn: $_showSecurityWarnings)
				Toggle(.localized("Show Compatibility Warnings"), systemImage: "iphone", isOn: $_showCompatibilityWarnings)
			} footer: {
				Text(.localized("Before adding an app, Feather checks that its bundle ID, version and file hash match what the source lists, and that it supports this version of iOS."))
			}
		}
	}
}
