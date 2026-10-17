//
//  ContentView.swift
//  LifeSpan
//
//  Created by Andrew Zhou on 5/13/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DailyAnimalView()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                BrowseView()
            }
            .tabItem { Label("Browse", systemImage: "list.bullet") }
        }
    }
}

// MARK: - Today

struct DailyAnimalView: View {
    @State private var viewModel = AnimalViewModel()

    var body: some View {
        ScrollView {
            if let animal = viewModel.animal {
                VStack(spacing: 16) {
                    Text(viewModel.isShowingDailyPick ? "Animal of the Day" : "Random Animal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    AnimalDetailContent(animal: animal)
                }
                .padding()
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView("Couldn't load", systemImage: "wifi.exclamationmark", description: Text(message))
            } else {
                ProgressView("Loading animal...").padding(.top, 80)
            }
        }
        .navigationTitle("LifeSpan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Another", systemImage: "shuffle") {
                    Task { await viewModel.loadRandomAnimal() }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .refreshable { await viewModel.loadDailyAnimal() }
        .task { if viewModel.animal == nil { await viewModel.loadDailyAnimal() } }
    }
}

// MARK: - Browse

struct BrowseView: View {
    @State private var viewModel = BrowseViewModel()

    var body: some View {
        List {
            ForEach(viewModel.animals) { animal in
                NavigationLink(value: animal) {
                    AnimalRow(animal: animal)
                }
                .task { await viewModel.loadMoreIfNeeded(current: animal) }
            }

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .overlay {
            if let message = viewModel.errorMessage, viewModel.animals.isEmpty {
                ContentUnavailableView("Couldn't load", systemImage: "wifi.exclamationmark", description: Text(message))
            } else if viewModel.animals.isEmpty && !viewModel.isLoading {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
        .navigationTitle("Browse")
        .navigationDestination(for: Animal.self) { animal in
            ScrollView { AnimalDetailContent(animal: animal).padding() }
                .navigationTitle(animal.name)
                .navigationBarTitleDisplayMode(.inline)
        }
        .searchable(text: $viewModel.searchText, prompt: "Search animals")
        .task(id: viewModel.searchText) {
            // Debounce typing; .task cancels the previous run when the text changes.
            if !viewModel.searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
                if Task.isCancelled { return }
            }
            await viewModel.reload()
        }
    }
}

struct AnimalRow: View {
    let animal: Animal

    var body: some View {
        HStack(spacing: 12) {
            AnimalImage(url: animal.imageURL)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(animal.name).font(.headline)
                if let lifespan = animal.lifespanText {
                    Text(lifespan).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Detail

struct AnimalDetailContent: View {
    let animal: Animal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnimalImage(url: animal.imageURL)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(animal.name).font(.largeTitle.bold())

            if let scientific = animal.details?.taxonomy?.scientificName {
                Text(scientific).italic().foregroundStyle(.secondary)
            }

            LifespanCard(animal: animal)

            FactsCard(animal: animal)

            if let description = animal.shortDescription {
                VStack(alignment: .leading, spacing: 6) {
                    Text("About").font(.headline)
                    Text(description)
                }
            }
        }
    }
}

/// The headline feature: how long this animal lives, next to a human lifespan.
struct LifespanCard: View {
    let animal: Animal
    private let humanYears = 79.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lifespan", systemImage: "hourglass").font(.headline)

            Text(animal.lifespanText ?? "Unknown").font(.title2.bold())

            if let years = animal.lifespanYears {
                LifespanBar(title: animal.name, years: years, maxYears: max(years, humanYears), tint: .green)
                LifespanBar(title: "Human", years: humanYears, maxYears: max(years, humanYears), tint: .blue)
                Text(comparison(years))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func comparison(_ years: Double) -> String {
        let ratio = years / humanYears
        if ratio >= 1.05 { return String(format: "Lives about %.1f× as long as a human.", ratio) }
        if ratio <= 0.95 { return String(format: "Lives about %.0f%% of a human lifetime.", ratio * 100) }
        return "About the same as a human lifetime."
    }
}

struct LifespanBar: View {
    let title: String
    let years: Double
    let maxYears: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(years < 1 ? String(format: "%.1f yrs", years) : "\(Int(years.rounded())) yrs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint).frame(width: max(6, proxy.size.width * years / maxYears))
                }
            }
            .frame(height: 8)
        }
    }
}

struct FactsCard: View {
    let animal: Animal

    private var rows: [(String, String)] {
        let c = animal.details?.characteristics
        let t = animal.details?.taxonomy
        let candidates: [(String, String?)] = [
            ("Habitat", animal.habitat),
            ("Diet", animal.diet),
            ("Locations", animal.details?.locations?.joined(separator: ", ")),
            ("Weight", c?.weight),
            ("Height", c?.height),
            ("Length", c?.length),
            ("Top speed", c?.topSpeed),
            ("Color", c?.color),
            ("Temperament", c?.temperament),
            ("Biggest threat", c?.biggestThreat),
            ("Distinctive feature", c?.mostDistinctiveFeature),
            ("Class", t?.class),
            ("Order", t?.order),
            ("Family", t?.family)
        ]
        return candidates.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.0) { label, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(label).foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(value).multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
            .cardStyle()
        }
    }
}

// MARK: - Shared bits

struct AnimalImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            default:
                ZStack { Color(.secondarySystemBackground); ProgressView() }
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Image("placeholderAnimal").resizable().scaledToFill()
    }
}

private extension View {
    func cardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
