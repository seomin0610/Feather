//
//  RemoteControlServer.swift
//  Feather
//
//  Created by Jeongmin on 20.09.2026.
//

import Foundation
import Vapor
import CoreData
import UIKit
import OSLog
import NimbleExtensions
import IDeviceSwift

// MARK: - Class
/// Feather Remote Protocol: JSON over HTTP, bearer token auth, disabled unless turned on in Settings.
///
/// Lets a computer drive imports, signing and installs from a CLI, either over the local network
/// or over USB with `iproxy <local> <port>`. Only alive while Feather itself is running.
final class RemoteControlServer: ObservableObject {
	static let shared = RemoteControlServer()

	static let version = 1
	static let enabledKey = "Feather.remote.enabled"
	static let portKey = "Feather.remote.port"
	static let tokenKey = "Feather.remote.token"
	static let defaultPort = 8420

	@Published private(set) var isRunning = false
	@Published private(set) var lastError: String?

	private var _app: Application?

	private init() {}

	// MARK: Settings
	static var port: Int {
		let stored = UserDefaults.standard.integer(forKey: portKey)
		return stored > 0 ? stored : defaultPort
	}

	static var token: String {
		if
			let existing = UserDefaults.standard.string(forKey: tokenKey),
			!existing.isEmpty
		{
			return existing
		}

		return regenerateToken()
	}

	@discardableResult
	static func regenerateToken() -> String {
		var bytes = [UInt8](repeating: 0, count: 24)
		_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

		let token = Data(bytes)
			.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")

		UserDefaults.standard.set(token, forKey: tokenKey)
		return token
	}

	var address: String {
		"http://\(ServerInstaller.getLocalAddress() ?? "127.0.0.1"):\(Self.port)"
	}

	// MARK: Lifecycle
	/// Starts or stops the server to match the toggle in Settings.
	func applyStoredState() {
		if UserDefaults.standard.bool(forKey: Self.enabledKey) {
			start()
		} else {
			stop()
		}
	}

	func restart() {
		stop()
		applyStoredState()
	}

	func start() {
		guard _app == nil else { return }

		do {
			let app = Application(ServerInstaller.env)
			app.threadPool = .init(numberOfThreads: 2)
			app.http.server.configuration.hostname = "0.0.0.0"
			app.http.server.configuration.address = .hostname("0.0.0.0", port: Self.port)
			app.http.server.configuration.port = Self.port
			app.http.server.configuration.tcpNoDelay = true
			app.routes.defaultMaxBodySize = "16mb"
			app.middleware.use(TokenMiddleware(token: Self.token))

			_routes(app)

			try app.server.start()
			_app = app
			isRunning = true
			lastError = nil
			Logger.misc.info("Remote server listening on \(self.address)")
		} catch {
			lastError = String(describing: error)
			isRunning = false
			Logger.misc.error("Remote server failed to start: \(error)")
		}
	}

	func stop() {
		guard let app = _app else { return }

		_app = nil
		isRunning = false

		DispatchQueue.global(qos: .userInitiated).async {
			app.server.shutdown()
			app.shutdown()
		}
	}
}

// MARK: - Class extension: Auth
extension RemoteControlServer {
	struct TokenMiddleware: AsyncMiddleware {
		let token: String

		func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
			guard
				let given = request.headers.bearerAuthorization?.token,
				Self.matches(given, token)
			else {
				throw Abort(.unauthorized, reason: "Missing or wrong bearer token")
			}

			return try await next.respond(to: request)
		}

		/// Constant time, so a wrong token doesn't leak how much of it was right.
		static func matches(_ lhs: String, _ rhs: String) -> Bool {
			let a = Array(lhs.utf8), b = Array(rhs.utf8)
			guard a.count == b.count else { return false }
			var diff: UInt8 = 0
			for i in a.indices { diff |= a[i] ^ b[i] }
			return diff == 0
		}
	}
}

// MARK: - Class extension: Models
extension RemoteControlServer {
	struct StatusModel: Content {
		let name: String
		let version: String
		let device: String
		let systemVersion: String
		let installationMethod: String
		let protocolVersion: Int
	}

	struct AppModel: Content {
		let uuid: String
		let name: String?
		let version: String?
		let identifier: String?
		let signed: Bool
		/// ISO 8601, Vapor would otherwise hand the CLI a raw timestamp
		let date: String?
	}

	struct AppListModel: Content {
		let apps: [AppModel]
	}

	struct CertificateModel: Content {
		let index: Int
		let uuid: String?
		let name: String?
		let expiration: String?
		let revoked: Bool
		let isDefault: Bool
	}

	struct CertificateListModel: Content {
		let certificates: [CertificateModel]
		let selected: Int
	}

	struct SourceModel: Content {
		let identifier: String?
		let name: String?
		let url: String?
	}

	struct SourceListModel: Content {
		let sources: [SourceModel]
	}

	struct SignRequestModel: Content {
		var certificate: Int?
		var name: String?
		var identifier: String?
		var version: String?
		var install: Bool?
	}

	struct CertificateRequestModel: Content {
		var p12: String
		var provision: String
		var password: String
		var name: String?
		var makeDefault: Bool?
	}

	struct SourceRequestModel: Content {
		var url: String
	}

	struct ProgressModel: Content {
		let identifier: String?
		let progress: Double?
	}
	
	struct OkModel: Content {
		let ok: Bool
		var message: String? = nil
	}
}

// MARK: - Class extension: Routes
extension RemoteControlServer {
	private func _routes(_ app: Application) {
		app.get("v1", "status") { _ async throws -> StatusModel in
			try await Self._status()
		}

		app.get("v1", "apps") { _ async throws -> AppListModel in
			try await Self._apps()
		}

		app.on(.POST, "v1", "apps", body: .stream) { req async throws -> AppModel in
			try await Self._import(req)
		}

		app.delete("v1", "apps", ":uuid") { req async throws -> OkModel in
			let uuid = try req.parameters.require("uuid")

			try await MainActor.run {
				guard let app = Self._find(uuid) else {
					throw Abort(.notFound, reason: "No app with uuid \(uuid)")
				}
				Storage.shared.deleteApp(for: app)
			}

			return OkModel(ok: true)
		}

		app.get("v1", "apps", ":uuid", "ipa") { req async throws -> Response in
			try await Self._export(req)
		}

		app.post("v1", "apps", ":uuid", "sign") { req async throws -> AppModel in
			let uuid = try req.parameters.require("uuid")
			let options = (try? req.content.decode(SignRequestModel.self)) ?? SignRequestModel()
			return try await Self._sign(uuid: uuid, options: options)
		}

		app.post("v1", "apps", ":uuid", "install") { req async throws -> OkModel in
			let uuid = try req.parameters.require("uuid")
			try await Self._install(uuid: uuid)
			return OkModel(ok: true, message: "Install started on the device")
		}

		app.get("v1", "apps", ":uuid", "progress") { req async throws -> ProgressModel in
			try await Self._progress(uuid: req.parameters.require("uuid"))
		}
		
		app.get("v1", "certificates") { _ async throws -> CertificateListModel in
			try await Self._certificates()
		}

		app.post("v1", "certificates") { req async throws -> CertificateListModel in
			try await Self._addCertificate(req.content.decode(CertificateRequestModel.self))
		}

		app.get("v1", "sources") { _ async throws -> SourceListModel in
			try await Self._sources()
		}

		app.post("v1", "sources") { req async throws -> OkModel in
			let body = try req.content.decode(SourceRequestModel.self)

			await MainActor.run {
				FR.handleSource(body.url) {}
			}

			return OkModel(ok: true, message: "Fetching source, failures are reported on the device")
		}
	}
}

// MARK: - Class extension: Handlers
extension RemoteControlServer {
	@MainActor
	private static func _find(_ uuid: String) -> AppInfoPresentable? {
		let signed: NSFetchRequest<Signed> = Signed.fetchRequest()
		signed.predicate = NSPredicate(format: "uuid == %@", uuid)
		signed.fetchLimit = 1

		if let app = try? Storage.shared.context.fetch(signed).first {
			return app
		}

		let imported: NSFetchRequest<Imported> = Imported.fetchRequest()
		imported.predicate = NSPredicate(format: "uuid == %@", uuid)
		imported.fetchLimit = 1
		return try? Storage.shared.context.fetch(imported).first
	}

	@MainActor
	private static func _model(_ app: AppInfoPresentable) -> AppModel {
		AppModel(
			uuid: app.uuid ?? "",
			name: app.name,
			version: app.version,
			identifier: app.identifier,
			signed: app.isSigned,
			date: app.date?.formatted(.iso8601)
		)
	}

	@MainActor
	private static func _newest<T: NSManagedObject>(_ type: T.Type) -> T? where T: AppInfoPresentable {
		let request = NSFetchRequest<T>(entityName: String(describing: type))
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}

	private static func _status() async throws -> StatusModel {
		await MainActor.run {
			StatusModel(
				name: Bundle.main.name,
				version: Bundle.main.version,
				device: MobileGestalt().getStringForName("PhysicalHardwareNameString") ?? "Unknown",
				systemVersion: UIDevice.current.systemVersion,
				installationMethod: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1
					? "idevice"
					: "server",
				protocolVersion: version
			)
		}
	}

	private static func _apps() async throws -> AppListModel {
		await MainActor.run {
			let signed: NSFetchRequest<Signed> = Signed.fetchRequest()
			signed.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]

			let imported: NSFetchRequest<Imported> = Imported.fetchRequest()
			imported.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]

			let apps = ((try? Storage.shared.context.fetch(signed)) ?? []).map { _model($0) }
				+ ((try? Storage.shared.context.fetch(imported)) ?? []).map { _model($0) }

			return AppListModel(apps: apps)
		}
	}

	/// Streams the uploaded package to disk first, an IPA is far too big to hold in memory.
	private static func _import(_ req: Request) async throws -> AppModel {
		let filename = req.query[String.self, at: "filename"] ?? "Upload.ipa"
		let ext = URL(fileURLWithPath: filename).pathExtension == "tipa" ? "tipa" : "ipa"

		// the client names this and the library bar shows it, so take the last component only
		var name = URL(fileURLWithPath: filename).lastPathComponent
		if name.isEmpty || name.hasPrefix(".") {
			name = "Upload.\(ext)"
		}

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherRemote_\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectoryIfNeeded(at: directory)
		let file = directory.appendingPathComponent(name)

		FileManager.default.createFile(atPath: file.path, contents: nil)
		let handle = try FileHandle(forWritingTo: file)

		do {
			for try await chunk in req.body {
				try handle.write(contentsOf: Data(chunk.readableBytesView))
			}
			try handle.close()
		} catch {
			try? handle.close()
			try? FileManager.default.removeItem(at: directory)
			throw error
		}

		defer { try? FileManager.default.removeItem(at: directory) }

		// a manual download id is what puts it in the bar at the top of the library
		let download = await MainActor.run {
			DownloadManager.shared.startArchive(
				from: file,
				id: "FeatherManualDownload_Remote_\(UUID().uuidString)"
			)
		}

		do {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				FR.handlePackageFile(file, download: download) { error in
					if let error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume()
					}
				}
			}
		} catch {
			await MainActor.run { DownloadManager.shared.cancelDownload(download) }
			throw error
		}

		await MainActor.run { DownloadManager.shared.cancelDownload(download) }

		return try await MainActor.run {
			guard let app = _newest(Imported.self) else {
				throw Abort(.internalServerError, reason: "Import finished but nothing was stored")
			}
			return _model(app)
		}
	}

	private static func _sign(uuid: String, options request: SignRequestModel) async throws -> AppModel {
		let (app, certificate, options) = try await MainActor.run { () -> (AppInfoPresentable, CertificatePair?, Options) in
			guard let app = _find(uuid) else {
				throw Abort(.notFound, reason: "No app with uuid \(uuid)")
			}

			let index = request.certificate ?? UserDefaults.standard.integer(forKey: "feather.selectedCert")
			let certificate = Storage.shared.getCertificate(for: index)
			var options = OptionsManager.shared.options

			// same preparation the signing screen does
			if
				options.ppqProtection,
				let identifier = app.identifier,
				certificate?.ppQCheck == true
			{
				options.appIdentifier = "\(identifier).\(options.ppqString)"
			}

			if
				let currentIdentifier = app.identifier,
				let newIdentifier = options.identifiers[currentIdentifier]
			{
				options.appIdentifier = newIdentifier
			}

			if
				let currentName = app.name,
				let newName = options.displayNames[currentName]
			{
				options.appName = newName
			}

			if let name = request.name { options.appName = name }
			if let identifier = request.identifier { options.appIdentifier = identifier }
			if let version = request.version { options.appVersion = version }

			return (app, certificate, options)
		}

		guard certificate != nil || options.signingOption != .default else {
			throw Abort(.badRequest, reason: "No certificate, pass \"certificate\" or set one in Feather")
		}

		// the library puts the signing screen up for this, and takes it down when the object is nil
		await MainActor.run {
			NotificationCenter.default.post(name: Notification.Name("Feather.remoteSigning"), object: uuid)
		}

		do {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				FR.signPackageFile(app, using: options, icon: nil, certificate: certificate) { error in
					if let error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume()
					}
				}
			}
			await _closeSigningScreen()
		} catch {
			await _closeSigningScreen()
			throw error
		}

		let signed = try await MainActor.run { () -> AppModel in
			if options.post_deleteAppAfterSigned, !app.isSigned {
				Storage.shared.deleteApp(for: app)
			}

			guard let app = _newest(Signed.self) else {
				throw Abort(.internalServerError, reason: "Signing finished but nothing was stored")
			}

			return _model(app)
		}

		if request.install == true {
			try await _install(uuid: signed.uuid)
		}

		return signed
	}

	private static func _closeSigningScreen() async {
		await MainActor.run {
			NotificationCenter.default.post(name: Notification.Name("Feather.remoteSigning"), object: nil)
		}
		// the install sheet can't come up while that screen is still on its way out
		try? await Task.sleep(nanoseconds: 600_000_000)
	}

	/// Hands off to the librarys install sheet, which owns both the server and idevice paths.
	private static func _install(uuid: String) async throws {
		try await MainActor.run {
			guard _find(uuid) != nil else {
				throw Abort(.notFound, reason: "No app with uuid \(uuid)")
			}

			guard UIApplication.shared.applicationState == .active else {
				throw Abort(.conflict, reason: "Feather must be open on the device to install")
			}

			NotificationCenter.default.post(name: Notification.Name("Feather.installApp"), object: uuid)
		}
	}

	/// installd's own number, the same one the install sheet polls.
	private static func _progress(uuid: String) async throws -> ProgressModel {
		let identifier = try await MainActor.run { () -> String? in
			guard let app = _find(uuid) else {
				throw Abort(.notFound, reason: "No app with uuid \(uuid)")
			}
			return app.identifier
		}
		
		// off the main thread, this call can block while installd answers
		return ProgressModel(
			identifier: identifier,
			progress: identifier.flatMap { UIApplication.installProgress(for: $0) }
		)
	}
	
	private static func _export(_ req: Request) async throws -> Response {
		let uuid = try req.parameters.require("uuid")

		let (app, filename) = try await MainActor.run { () -> (AppInfoPresentable, String) in
			guard let app = _find(uuid) else {
				throw Abort(.notFound, reason: "No app with uuid \(uuid)")
			}
			// this ends up in a header, so keep it to characters that can't break out of one
			let name = "\(app.name ?? "App")_\(app.version ?? "0")"
				.map { $0.isLetter || $0.isNumber ? $0 : "_" }
			return (app, "\(String(name)).ipa")
		}

		let viewModel = await InstallerStatusViewModel(isIdevice: false)
		let handler = await ArchiveHandler(app: app, viewModel: viewModel)
		try await handler.move()
		let package = try await handler.archive()

		let response = req.fileio.streamFile(at: package.path) { _ in
			try? FileManager.default.removeItem(at: package.deletingLastPathComponent())
		}

		response.headers.contentDisposition = HTTPHeaders.ContentDisposition(.attachment, filename: filename)
		return response
	}

	private static func _certificates() async throws -> CertificateListModel {
		await MainActor.run {
			let certificates = Storage.shared.getAllCertificates().enumerated().map { index, cert in
				CertificateModel(
					index: index,
					uuid: cert.uuid,
					name: cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name,
					expiration: cert.expiration?.formatted(.iso8601),
					revoked: cert.revoked,
					isDefault: cert.isDefault
				)
			}

			return CertificateListModel(
				certificates: certificates,
				selected: UserDefaults.standard.integer(forKey: "feather.selectedCert")
			)
		}
	}

	private static func _addCertificate(_ body: CertificateRequestModel) async throws -> CertificateListModel {
		guard
			let p12 = FileManager.default.decodeAndWrite(base64: body.p12, pathComponent: ".p12"),
			let provision = FileManager.default.decodeAndWrite(base64: body.provision, pathComponent: ".mobileprovision")
		else {
			throw Abort(.badRequest, reason: "p12 and provision must be base64")
		}

		guard FR.checkPasswordForCertificate(for: p12, with: body.password, using: provision) else {
			throw Abort(.badRequest, reason: "Wrong password for this certificate")
		}

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			FR.handleCertificateFiles(
				p12URL: p12,
				provisionURL: provision,
				p12Password: body.password,
				certificateName: body.name ?? "",
				isDefault: body.makeDefault ?? false
			) { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}

		return try await _certificates()
	}

	private static func _sources() async throws -> SourceListModel {
		await MainActor.run {
			SourceListModel(sources: Storage.shared.getSources().map {
				SourceModel(
					identifier: $0.identifier,
					name: $0.name,
					url: $0.sourceURL?.absoluteString
				)
			})
		}
	}
}
