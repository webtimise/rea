import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CityResult: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let detail: String
    public let latitude: Double
    public let longitude: Double
    public let countryCode: String?
}

public enum CitySearchError: Error, Equatable {
    case badStatus(Int)
    case unreadableResponse
}

/// Forward geocoding through OpenStreetMap Nominatim. Its usage policy
/// requires an identifying User-Agent and at most one request per second,
/// so callers search on submit rather than per keystroke.
public struct CitySearch {
    public let endpoint: URL
    public let userAgent: String
    let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://nominatim.openstreetmap.org/search")!,
        userAgent: String,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.userAgent = userAgent
        self.session = session
    }

    public func request(for query: String, limit: Int = 8) -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func search(_ query: String) async throws -> [CityResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let (data, response) = try await session.data(for: request(for: trimmed))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CitySearchError.badStatus(http.statusCode)
        }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> [CityResult] {
        struct Place: Decodable {
            struct Address: Decodable {
                let city: String?
                let town: String?
                let village: String?
                let country: String?
                let country_code: String?
            }

            let place_id: Int?
            let lat: String
            let lon: String
            let name: String?
            let display_name: String
            let address: Address?
        }

        let places: [Place]
        do {
            places = try JSONDecoder().decode([Place].self, from: data)
        } catch {
            throw CitySearchError.unreadableResponse
        }
        return places.compactMap { place in
            guard let latitude = Double(place.lat), let longitude = Double(place.lon) else { return nil }
            let address = place.address
            let locality = [place.name, address?.city, address?.town, address?.village]
                .compactMap { $0 }
                .first { !$0.isEmpty }
                ?? place.display_name.components(separatedBy: ",").first ?? place.display_name
            return CityResult(
                id: place.place_id.map(String.init) ?? "\(latitude),\(longitude)",
                name: locality.trimmingCharacters(in: .whitespaces),
                detail: place.display_name,
                latitude: latitude,
                longitude: longitude,
                countryCode: address?.country_code?.uppercased()
            )
        }
    }
}
