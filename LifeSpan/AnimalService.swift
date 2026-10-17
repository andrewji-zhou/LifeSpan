//
//  AnimalService.swift
//  LifeSpan
//
//  Talks to Supabase's PostgREST endpoint for the `animals` table.
//

import Foundation

struct AnimalService {
    enum ServiceError: LocalizedError {
        case badURL
        case server(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .badURL: return "Couldn't build the request."
            case .server(let code): return "Server returned status \(code). Check the anon key and RLS policy."
            case .empty: return "No animals found."
            }
        }
    }

    static let shared = AnimalService()

    private let baseURL = URL(string: Secrets.supabaseURL)!
    private let decoder = JSONDecoder()

    /// Index of today's pick among `total` animals. The app and the widget both use this so they always agree.
    static func dailyIndex(total: Int, on date: Date = .now) -> Int {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return day % max(total, 1)
    }

    /// Total number of rows in `animals`.
    func count() async throws -> Int {
        var request = try makeRequest(query: [URLQueryItem(name: "select", value: "id")])
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        request.setValue("0-0", forHTTPHeaderField: "Range")

        let (_, response) = try await send(request)
        try check(response)
        // Content-Range looks like "0-0/1449"
        guard let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last.flatMap({ Int($0) }) else {
            throw ServiceError.empty
        }
        return total
    }

    /// One page of animals ordered by name, optionally filtered by a name search.
    func animals(search: String = "", offset: Int = 0, limit: Int = 30) async throws -> [Animal] {
        var query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "name.asc"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        let term = search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            query.append(URLQueryItem(name: "name", value: "ilike.*\(term)*"))
        }
        return try await fetch(query)
    }

    /// The animal at a stable position when ordered by id. Used for the daily pick and random pick.
    func animal(atIndex index: Int) async throws -> Animal {
        let query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "id.asc"),
            URLQueryItem(name: "offset", value: String(index)),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let first = try await fetch(query).first else { throw ServiceError.empty }
        return first
    }

    // MARK: - Plumbing

    private func fetch(_ query: [URLQueryItem]) async throws -> [Animal] {
        let request = try makeRequest(query: query)
        let (data, response) = try await send(request)
        try check(response)
        return try decoder.decode([Animal].self, from: data)
    }

    private func makeRequest(query: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/animals"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw ServiceError.badURL }

        var request = URLRequest(url: url)
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Short timeout plus retries: a stalled HTTP/3 (QUIC) attempt, common in the simulator,
    /// times out and the retry falls back to HTTP/2.
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = 8
        var lastError: Error?
        for _ in 0..<3 {
            do {
                return try await URLSession.shared.data(for: request)
            } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                lastError = error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ServiceError.server(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.server(http.statusCode) }
    }
}
