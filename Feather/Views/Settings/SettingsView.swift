//
//  SettingsView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import NimbleViews
import UIKit
import Darwin
import IDeviceSwift

// MARK: - View
struct SettingsView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	@State private var _currentIcon: String? = UIApplication.shared.alternateIconName
	@State private var _isImportingDatabasePresenting = false
	
	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>
	
	private var selectedCertificate: CertificatePair? {
		guard
			_storedSelectedCert >= 0,
			_storedSelectedCert < _certificates.count
		else {
			return nil
		}
		return _certificates[_storedSelectedCert]
	}
	private let _githubUrl = "https://github.com/seomin0610/Feather"
    
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Settings")) {
			Form {
				_feedback()
                
				Section {
					NavigationLink(destination: AppearanceView()) {
						Label(.localized("Appearance"), systemImage: "paintbrush")
					}
					NavigationLink(destination: AppIconView(currentIcon: $_currentIcon)) {
						Label(.localized("App Icon"), systemImage: "app.badge")
					}
				}
                
				NBSection(.localized("Certificates")) {
                    
					if let cert = selectedCertificate {
						CertificatesCellView(cert: cert)
					} else {
						Text(.localized("No Certificate"))
							.font(.footnote)
							.foregroundColor(.disabled())
					}
					NavigationLink(destination: CertificatesView()) {
						Label(.localized("Certificates"), systemImage: "checkmark.seal")
					}
                 
				} footer: {
					Text(.localized("Add and manage certificates used for signing applications."))
				}
                
				NBSection(.localized("Features")) {
					NavigationLink(destination: ConfigurationView()) {
						Label(.localized("Signing Options"), systemImage: "signature")
					}
					NavigationLink(destination: ArchiveView()) {
						Label(.localized("Archive & Compression"), systemImage: "archivebox")
					}
					NavigationLink(destination: InstallationView()) {
						Label(.localized("Installation"), systemImage: "arrow.down.circle")
					}
					NavigationLink(destination: RemoteView()) {
						Label(.localized("Remote CLI"), systemImage: "terminal")
					}
				} footer: {
					Text(.localized("Configure the apps way of installing, its zip compression levels, and custom modifications to apps."))
				}
                
				_directories()
                
				Section {
					NavigationLink(destination: ResetView()) {
						Label(.localized("Reset"), systemImage: "trash")
					}
				} footer: {
					Text(.localized("Reset the applications sources, certificates, apps, and general contents."))
				}
				
				_database()

				#if DEBUG
				Section {
					Button("Reset Onboarding", systemImage: "arrow.counterclockwise") {
						LocalCertificateNoticeView.resetShown()
					}
					Button("Preview Progress Activity", systemImage: "progress.indicator") {
						Task {
							let id = "FeatherDebugPreview"
							LiveTask.start(id, title: "Feather", subtitle: .localized("Signing"), goal: .localized("Signing Complete"))
							for percent in 1...100 {
								try? await Task.sleep(nanoseconds: 100_000_000)
								LiveTask.update(id, progress: Double(percent) / 100, subtitle: .localized("Signing"))
							}
						}
					}
					Button("Preview Download Activity", systemImage: "arrow.down.circle") {
						Task {
							let id = "FeatherDebugPreviewDownload"
							LiveTask.start(
								id,
								title: "Feather.ipa",
								subtitle: .localized("Downloading"),
								goal: .localized("Download Complete"),
								stages: [.localized("Downloading"), .localized("Extracting")]
							)
							for (stage, step) in [String.localized("Downloading"), .localized("Extracting")].enumerated() {
								for percent in 1...100 {
									try? await Task.sleep(nanoseconds: 60_000_000)
									LiveTask.update(id, progress: Double(percent) / 100, subtitle: step, stage: stage)
								}
							}
						}
					}
				} header: {
					Text(verbatim: "Debug")
				} footer: {
					Text(verbatim: "Reset Onboarding shows the local certificate notice again on the next launch. The previews run a fake signing or download job for about 10 seconds, leave the app to see them.")
				}
				#endif
			}
			.sheet(isPresented: $_isImportingDatabasePresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.data],
					onDocumentsPicked: { urls in
						guard let url = urls.first else { return }
						_importDatabase(from: url)
					}
				)
				.ignoresSafeArea()
			}
		}
	}
}

// MARK: - View extension
extension SettingsView {
	@ViewBuilder
	private func _feedback() -> some View {
		Section {
			NavigationLink(destination: AboutView()) {
				Label {
					Text(verbatim: .localized("About %@", arguments: Bundle.main.name))
				} icon: {
					FRAppIconView(size: 23)
				}
			}
            
			Button(.localized("Submit Feedback"), systemImage: "safari") {
				UIApplication.open(URL(string: "\(_githubUrl)/issues/new/choose")!)
			}
			Button(.localized("GitHub Repository"), systemImage: "safari") {
				UIApplication.open(_githubUrl)
			}
		} footer: {
			Text(.localized("If any issues occur within the app please report it via the GitHub repository. When submitting an issue, make sure to submit detailed information."))
		}
	}
    
	@ViewBuilder
	private func _database() -> some View {
		Section {
			Button(.localized("Export Database"), systemImage: "square.and.arrow.up") {
				do {
					UIActivityViewController.show(activityItems: [try Storage.shared.exportDatabase()])
				} catch {
					UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
				}
			}
			Button(.localized("Import Database"), systemImage: "square.and.arrow.down") {
				_isImportingDatabasePresenting = true
			}

			if Storage.hasFeatherPlusData {
				Button(.localized("Migrate from FeatherPlus"), systemImage: "arrow.down.doc") {
					ResetView.resetAlert(
						title: .localized("Migrate from FeatherPlus"),
						message: .localized("FeatherPlus data was found. Migrating replaces the current apps, certificates and sources with it and restarts the app.")
					) {
						UserDefaults.standard.set(true, forKey: Storage.pendingFeatherPlusMigrationKey)
					}
				}
			}
		} footer: {
			Text(.localized("The database holds your lists of apps, certificates and sources, not the files themselves. Importing replaces the current database and restarts the app."))
		}
	}

	private func _importDatabase(from url: URL) {
		do {
			try Storage.validateDatabase(at: url)
		} catch {
			UIAlertController.showAlertWithOk(
				title: .localized("Import Database"),
				message: .localized("This file isn't a Feather database.")
			)
			return
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			ResetView.resetAlert(
				title: .localized("Import Database"),
				message: .localized("The current apps, certificates and sources will be replaced with the imported ones and the app will restart.")
			) {
				do {
					try Storage.stageDatabaseImport(from: url)
				} catch {
					print("Failed to stage database import: \(error)")
				}
			}
		}
	}

	@ViewBuilder
	private func _directories() -> some View {
		NBSection(.localized("Misc")) {
			Button(.localized("Open Documents"), systemImage: "folder") {
				UIApplication.open(URL.documentsDirectory.toSharedDocumentsURL()!)
			}
			Button(.localized("Open Archives"), systemImage: "folder") {
				UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
			}
			Button(.localized("Open Certificates"), systemImage: "folder") {
				UIApplication.open(FileManager.default.certificates.toSharedDocumentsURL()!)
			}
		} footer: {
			Text(.localized("All of the apps files are contained in the documents directory, here are some quick links to these."))
		}
	}
}
