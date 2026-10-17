//
//  Animal.swift
//  LifeSpan
//
//  Created by Andrew Zhou on 5/14/25.
//

import Foundation

/// One row of the Supabase `animals` table.
struct Animal: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let habitat: String?
    let diet: String?
    let imageURL: URL?
    let description: String?
    let details: Details?

    enum CodingKeys: String, CodingKey {
        case id, name, habitat, diet, description
        case imageURL = "image_url"
        case details = "json_data"
    }

    /// The raw API Ninjas payload stored in `json_data`. Every field is optional because
    /// the API leaves out whatever it doesn't know about an animal.
    struct Details: Codable, Hashable {
        let locations: [String]?
        let taxonomy: Taxonomy?
        let characteristics: Characteristics?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            locations = try? c.decodeIfPresent([String].self, forKey: .locations)
            taxonomy = try? c.decodeIfPresent(Taxonomy.self, forKey: .taxonomy)
            characteristics = try? c.decodeIfPresent(Characteristics.self, forKey: .characteristics)
        }

        enum CodingKeys: String, CodingKey { case locations, taxonomy, characteristics }
    }

    struct Taxonomy: Codable, Hashable {
        let kingdom: String?
        let phylum: String?
        let `class`: String?
        let order: String?
        let family: String?
        let genus: String?
        let scientificName: String?

        enum CodingKeys: String, CodingKey {
            case kingdom, phylum, `class`, order, family, genus
            case scientificName = "scientific_name"
        }
    }

    struct Characteristics: Codable, Hashable {
        let prey: String?
        let estimatedPopulationSize: String?
        let biggestThreat: String?
        let mostDistinctiveFeature: String?
        let temperament: String?
        let color: String?
        let skinType: String?
        let lifespan: String?
        let weight: String?
        let height: String?
        let length: String?
        let topSpeed: String?

        enum CodingKeys: String, CodingKey {
            case prey, temperament, color, lifespan, weight, height, length
            case estimatedPopulationSize = "estimated_population_size"
            case biggestThreat = "biggest_threat"
            case mostDistinctiveFeature = "most_distinctive_feature"
            case skinType = "skin_type"
            case topSpeed = "top_speed"
        }
    }
}

extension Animal {
    var lifespanText: String? { details?.characteristics?.lifespan }

    /// Midpoint of the lifespan string in years ("10-13 years" -> 11.5), or nil if unparseable.
    var lifespanYears: Double? {
        guard let text = lifespanText?.lowercased() else { return nil }
        let numbers = text
            .replacingOccurrences(of: ",", with: "")
            .matches(of: /\d+(\.\d+)?/)
            .compactMap { Double($0.output.0) }
        guard !numbers.isEmpty else { return nil }

        var value = numbers.count >= 2 ? (numbers[0] + numbers[1]) / 2 : numbers[0]
        if text.contains("month") { value /= 12 }
        else if text.contains("week") { value /= 52 }
        else if text.contains("day") { value /= 365 }
        return value
    }

    /// First sentence or two of the Wikipedia blurb, for list rows.
    var shortDescription: String? {
        guard let description, !description.isEmpty else { return nil }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
