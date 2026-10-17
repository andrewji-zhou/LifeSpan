//
//  AnimalViewModel.swift
//  LifeSpan
//
//  Created by Andrew Zhou on 5/14/25.
//

import Foundation
import Observation

/// Drives the "Animal of the Day" tab.
@Observable
@MainActor
final class AnimalViewModel {
    private(set) var animal: Animal?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isShowingDailyPick = true

    private let service = AnimalService.shared
    private var total = 0

    /// Everyone gets the same animal on the same calendar day.
    func loadDailyAnimal() async {
        await load { total in
            self.isShowingDailyPick = true
            return AnimalService.dailyIndex(total: total)
        }
    }

    func loadRandomAnimal() async {
        await load { total in
            self.isShowingDailyPick = false
            return Int.random(in: 0..<total)
        }
    }

    private func load(pickIndex: (Int) -> Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if total == 0 { total = try await service.count() }
            guard total > 0 else { throw AnimalService.ServiceError.empty }
            animal = try await service.animal(atIndex: pickIndex(total))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Drives the searchable "Browse" tab.
@Observable
@MainActor
final class BrowseViewModel {
    private(set) var animals: [Animal] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var searchText = ""

    private let service = AnimalService.shared
    private let pageSize = 30
    private var reachedEnd = false

    func reload() async {
        animals = []
        reachedEnd = false
        await loadMore()
    }

    /// Call as rows appear; fetches the next page when the user nears the bottom.
    func loadMoreIfNeeded(current animal: Animal) async {
        guard let index = animals.firstIndex(of: animal), index >= animals.count - 5 else { return }
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let query = searchText
        do {
            let page = try await service.animals(search: query, offset: animals.count, limit: pageSize)
            // Drop the result if the search changed while we were waiting.
            guard query == searchText else { return }
            animals += page
            reachedEnd = page.count < pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
