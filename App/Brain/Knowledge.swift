import Foundation

/// Looks things up on free public websites (DuckDuckGo, Wikipedia, Open-Meteo weather) when
/// internet is allowed. No AI service is involved. Everything it finds is saved on the phone,
/// so Helper keeps what it learned and can answer again without internet.
@MainActor
final class Knowledge {
    private struct Entry: Codable {
        var text: String
        var date: Date
    }

    private var learned: [String: Entry]
    private let fileURL: URL
    private let session: URLSession

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("learned.json")
        learned = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: fileURL))) ?? [:]
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    var learnedCount: Int { learned.count }

    func forgetLearned() {
        learned = [:]
        save()
    }

    /// A short text about `query`, from what Helper already learned or from the web.
    func lookup(_ query: String, online: Bool) async -> String? {
        let key = FuzzyMatch.normalize(query)
        let known = learned[key]
        // Facts can change, so re-check anything older than a week when online.
        if let known, !online || Date().timeIntervalSince(known.date) < 7 * 86_400 { return known.text }
        guard online else { return nil }

        var parts: [String] = []
        if let instant = await duckDuckGo(query) { parts.append(instant) }
        if let article = await wikipedia(query) { parts.append(article) }
        guard !parts.isEmpty else { return known?.text }

        let text = String(parts.joined(separator: "\n").prefix(1400))
        learned[key] = Entry(text: text, date: Date())
        if learned.count > 300, let oldest = learned.min(by: { $0.value.date < $1.value.date })?.key {
            learned[oldest] = nil
        }
        save()
        return text
    }

    /// Current weather and a two-day forecast for a place.
    func weather(_ place: String, online: Bool) async -> String? {
        guard online, !place.isEmpty else { return nil }
        var geocode = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocode.queryItems = [URLQueryItem(name: "name", value: place), URLQueryItem(name: "count", value: "1")]
        guard let found = await fetchJSON(geocode.url!) as? [String: Any],
              let spot = (found["results"] as? [[String: Any]])?.first,
              let latitude = spot["latitude"] as? Double,
              let longitude = spot["longitude"] as? Double else { return nil }
        let name = [spot["name"] as? String, spot["country"] as? String].compactMap { $0 }.joined(separator: ", ")

        let us = Locale.current.measurementSystem == .us
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: us ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: us ? "mph" : "kmh"),
        ]
        guard let data = await fetchJSON(forecast.url!) as? [String: Any],
              let now = data["current"] as? [String: Any],
              let daily = data["daily"] as? [String: Any] else { return nil }

        let unit = us ? "°F" : "°C"
        func number(_ value: Any?) -> Int? { (value as? Double).map { Int($0.rounded()) } }
        func day(_ index: Int) -> String? {
            guard let highs = daily["temperature_2m_max"] as? [Double], let lows = daily["temperature_2m_min"] as? [Double],
                  let codes = daily["weather_code"] as? [Int], highs.count > index, lows.count > index, codes.count > index else { return nil }
            let rain = (daily["precipitation_probability_max"] as? [Int])?[safe: index].map { ", \($0)% chance of rain" } ?? ""
            return "\(Self.describe(codes[index])), high \(Int(highs[index].rounded()))\(unit), low \(Int(lows[index].rounded()))\(unit)\(rain)"
        }

        var text = "Weather in \(name) right now: "
        if let temp = number(now["temperature_2m"]) { text += "\(temp)\(unit)" }
        if let feels = number(now["apparent_temperature"]) { text += " (feels like \(feels)\(unit))" }
        if let code = now["weather_code"] as? Int { text += ", \(Self.describe(code))" }
        if let wind = number(now["wind_speed_10m"]) { text += ", wind \(wind) \(us ? "mph" : "km/h")" }
        text += "."
        if let today = day(0) { text += " Today: \(today)." }
        if let tomorrow = day(1) { text += " Tomorrow: \(tomorrow)." }
        return text
    }

    // MARK: - Sources

    private func duckDuckGo(_ query: String) async -> String? {
        var url = URLComponents(string: "https://api.duckduckgo.com/")!
        url.queryItems = [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"), URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let json = await fetchJSON(url.url!) as? [String: Any] else { return nil }
        let text = [json["Answer"] as? String, json["AbstractText"] as? String]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private func wikipedia(_ query: String) async -> String? {
        var search = URLComponents(string: "https://en.wikipedia.org/w/rest.php/v1/search/page")!
        search.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "1")]
        guard let results = await fetchJSON(search.url!) as? [String: Any],
              let key = ((results["pages"] as? [[String: Any]])?.first)?["key"] as? String,
              let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))),
              let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
              let summary = await fetchJSON(summaryURL) as? [String: Any],
              let extract = summary["extract"] as? String, !extract.isEmpty else { return nil }
        return "\(summary["title"] as? String ?? key): \(extract)"
    }

    private func fetchJSON(_ url: URL) async -> Any? {
        var request = URLRequest(url: url)
        request.setValue("HeyHelper/1.1 (personal iPhone assistant)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: result.0)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(learned) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Open-Meteo weather codes in words.
    private static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "clear sky"
        case 1, 2: return "partly cloudy"
        case 3: return "cloudy"
        case 45, 48: return "foggy"
        case 51...57: return "drizzle"
        case 61...67: return "rain"
        case 71...77: return "snow"
        case 80...82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95...99: return "thunderstorms"
        default: return "mixed weather"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
