//
//  LifeSpanWidget.swift
//  LifeSpanWidget
//
//  Animal of the Day widget. Fetches the same daily pick as the app straight from Supabase.
//  Needs Animal.swift, AnimalService.swift and Secrets.swift in this target.
//

import SwiftUI
import UIKit
import WidgetKit

// MARK: - Timeline

struct AnimalEntry: TimelineEntry {
    let date: Date
    let animal: Animal?
    let image: UIImage?
}

extension AnimalEntry {
    static let placeholder = AnimalEntry(
        date: .now,
        animal: Animal(id: 0, name: "Giant Tortoise", habitat: nil, diet: nil, imageURL: nil,
                       description: nil,
                       details: nil),
        image: nil
    )
}

struct AnimalProvider: TimelineProvider {
    func placeholder(in context: Context) -> AnimalEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (AnimalEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        Task { completion(await loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnimalEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            // Refresh just after midnight when the daily animal changes. If loading failed, try again sooner.
            let nextMidnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 5),
                                                         matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600 * 6)
            let next = entry.animal == nil ? Date.now.addingTimeInterval(15 * 60) : nextMidnight
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func loadEntry() async -> AnimalEntry {
        do {
            let service = AnimalService.shared
            let total = try await service.count()
            let animal = try await service.animal(atIndex: AnimalService.dailyIndex(total: total))
            return AnimalEntry(date: .now, animal: animal, image: await downloadImage(animal.imageURL))
        } catch {
            return AnimalEntry(date: .now, animal: nil, image: nil)
        }
    }

    /// Widgets can't use AsyncImage, so the picture is downloaded up front.
    private func downloadImage(_ url: URL?) async -> UIImage? {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Views

struct LifeSpanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AnimalEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var lifespan: String { entry.animal?.lifespanText ?? "Lifespan unknown" }

    private var photo: some View {
        Group {
            if let image = entry.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("placeholderAnimal").resizable().scaledToFill()
            }
        }
    }

    // Home screen

    private var small: some View {
        ZStack(alignment: .bottomLeading) {
            photo
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.animal?.name ?? "LifeSpan").font(.headline).lineLimit(2)
                Label(lifespan, systemImage: "hourglass").font(.caption2).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .containerBackground(for: .widget) { Color.black }
    }

    private var medium: some View {
        HStack(spacing: 0) {
            photo.frame(maxWidth: 150, maxHeight: .infinity).clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text("ANIMAL OF THE DAY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(entry.animal?.name ?? "Open LifeSpan").font(.title3.bold()).lineLimit(2)
                Label(lifespan, systemImage: "hourglass").font(.subheadline).foregroundStyle(.green)
                if let years = entry.animal?.lifespanYears {
                    Text(humanComparison(years)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    // Lock screen

    private var rectangular: some View {
        VStack(alignment: .leading) {
            Text(entry.animal?.name ?? "LifeSpan").font(.headline).lineLimit(1)
            Label(lifespan, systemImage: "hourglass").font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let years = entry.animal?.lifespanYears {
                VStack(spacing: 0) {
                    Text(years < 10 ? String(format: "%.1f", years) : "\(Int(years.rounded()))").font(.title3.bold())
                    Text("yrs").font(.caption2)
                }
            } else {
                Image(systemName: "pawprint.fill")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Text("\(entry.animal?.name ?? "LifeSpan"): \(lifespan)")
    }

    private func humanComparison(_ years: Double) -> String {
        let ratio = years / 79
        return ratio >= 1.05 ? String(format: "%.1f× a human lifetime", ratio)
                             : String(format: "%.0f%% of a human lifetime", ratio * 100)
    }
}

// MARK: - Widget

struct LifeSpanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LifeSpanWidget", provider: AnimalProvider()) { entry in
            LifeSpanWidgetView(entry: entry)
        }
        .configurationDisplayName("Animal of the Day")
        .description("See today's animal and how long it lives.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    LifeSpanWidget()
} timeline: {
    AnimalEntry.placeholder
}
