//
//  FeatherServerInstaller.swift
//  Feather
//

import Foundation

/// Response from the signer server after uploading an IPA.
struct FeatherInstallManifest: Decodable {
	let manifestUrl: URL?
	let installUrl: URL
	let ipaUrl: URL?
	let title: String?
	let bundleId: String?
	let version: String?
	let expiresAt: String?
	let remainingToday: Int?
}

/// Uploads an IPA to the signer server, which hosts an OTA manifest for it.
/// Used for installing Feather itself, which can't be installed by its own local server.
enum FeatherServerInstaller {
	static let endpoint = URL(string: "https://signer.waterwave.space/api/manifest")!

	static func upload(
		ipa: URL,
		progress: @escaping (Double) -> Void
	) async throws -> FeatherInstallManifest {
		let boundary = "Boundary-\(UUID().uuidString)"

		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		var body = Data()
		body.append(Data("--\(boundary)\r\n".utf8))
		body.append(Data("Content-Disposition: form-data; name=\"ipa\"; filename=\"app.ipa\"\r\n".utf8))
		body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
		body.append(try Data(contentsOf: ipa, options: .mappedIfSafe))
		body.append(Data("\r\n--\(boundary)--\r\n".utf8))

		let (data, response) = try await URLSession.shared.upload(
			for: request,
			from: body,
			delegate: _UploadProgressDelegate(progress: progress)
		)

		guard let http = response as? HTTPURLResponse else {
			throw FeatherServerInstallerError(message: "Invalid server response")
		}

		guard (200..<300).contains(http.statusCode) else {
			throw FeatherServerInstallerError(message: _errorMessage(from: data) ?? "HTTP \(http.statusCode)")
		}

		do {
			return try JSONDecoder().decode(FeatherInstallManifest.self, from: data)
		} catch {
			throw FeatherServerInstallerError(message: _errorMessage(from: data) ?? error.localizedDescription)
		}
	}

	private static func _errorMessage(from data: Data) -> String? {
		if
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let message = (json["error"] ?? json["message"]) as? String
		{
			return message
		}

		let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
		return text?.isEmpty == false ? text : nil
	}
}

struct FeatherServerInstallerError: LocalizedError, CustomStringConvertible {
	let message: String

	var errorDescription: String? { message }
	var description: String { message }
}

private final class _UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
	let progress: (Double) -> Void

	init(progress: @escaping (Double) -> Void) {
		self.progress = progress
	}

	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didSendBodyData bytesSent: Int64,
		totalBytesSent: Int64,
		totalBytesExpectedToSend: Int64
	) {
		guard totalBytesExpectedToSend > 0 else { return }
		progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
	}
}
