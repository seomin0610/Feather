//
//  LocalCertificateAuthority+Profile.swift
//  Feather
//
//  Created by Jeongmin on 25.10.2026.
//

import SafariServices
import UIKit
import Vapor

extension LocalCertificateAuthority {
	@MainActor private static var _profileServer: Application?

	@MainActor
	static func openProfile() throws {
		_stopProfileServer()

		let data = try profileData()
		let port = Int.random(in: 8001...9000)
		let app = Application(ServerInstaller.env)
		app.http.server.configuration.hostname = "127.0.0.1"
		app.http.server.configuration.port = port
		app.get("FeatherLocalCA.mobileconfig") { _ in
			Response(
				status: .ok,
				headers: ["Content-Type": "application/x-apple-aspen-config"],
				body: .init(data: data)
			)
		}

		try app.server.start()
		_profileServer = app

		// other browsers only download the file, so keep it in Safari
		let url = URL(string: "http://127.0.0.1:\(port)/FeatherLocalCA.mobileconfig")!
		UIApplication.topViewController()?.present(SFSafariViewController(url: url), animated: true)

		DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
			guard _profileServer === app else { return }
			_stopProfileServer()
		}
	}

	@MainActor
	private static func _stopProfileServer() {
		guard let app = _profileServer else { return }
		_profileServer = nil
		app.server.shutdown()
		app.shutdown()
	}
}
