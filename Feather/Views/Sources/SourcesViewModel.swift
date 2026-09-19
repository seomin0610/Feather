//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()
	
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	
	private let _dataService = NBFetchService()
	
	var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]
	@Published var errors: [AltSource: Error] = [:]
	
	func fetchSources(_ sources: some Collection<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		guard isFinished else { return }
		
		// check if sources to be fetched are the same as before, if yes, return
		// also skip check if refresh is true
		if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }
		
		// isfinished is used to prevent multiple fetches at the same time
		isFinished = false
		defer { isFinished = true }
		
		let sourcesArray = Array(sources)
		
		await MainActor.run {
			for source in sourcesArray {
				self.sources[source] = nil
				self.errors[source] = nil
			}
		}
		
		for startIndex in stride(from: 0, to: sourcesArray.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, sourcesArray.count)
			let batch = sourcesArray[startIndex..<endIndex]
			
			let batchResults = await withTaskGroup(of: (AltSource, RepositoryDataHandler).self, returning: [(AltSource, RepositoryDataHandler)].self) { group in
				for source in batch {
					group.addTask {
						guard let url = source.sourceURL else {
							return (source, .failure(URLError(.badURL)))
						}
						
						return await withCheckedContinuation { continuation in
							self._dataService.fetch(from: url) { (result: RepositoryDataHandler) in
								continuation.resume(returning: (source, result))
							}
						}
					}
				}
				
				var results = [(AltSource, RepositoryDataHandler)]()
				for await result in group {
					results.append(result)
				}
				return results
			}
			
			await MainActor.run {
				for (source, result) in batchResults {
					switch result {
					case .success(let repo):
						self.sources[source] = repo
					case .failure(let error):
						self.errors[source] = error
					}
				}
			}
		}
	}
}
