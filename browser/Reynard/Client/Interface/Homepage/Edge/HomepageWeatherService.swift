//
//  HomepageWeatherService.swift
//  Reynard
//
//  Live weather for the Edge style homepage. Nothing is cached: every load
//  hits the MSN feed and the MSN hourly page.
//

import Foundation

struct HomepageWeatherSnapshot {
    struct Condition {
        let temperature: Double
        let feelsLike: Double
        let summary: String
        let symbol: String
        let isDaytime: Bool
        let humidity: Double
        let windSpeed: Double
        let windSummary: String
        let pressure: Double
        let uvIndex: Double
        let uvSummary: String
        let aqi: Double
        let aqiSeverity: String
    }
    
    struct Day {
        let date: Date?
        let summary: String
        let high: Double
        let low: Double
        let symbol: String
        let isDaytime: Bool
        let aqi: Double
    }
    
    struct Hour {
        let date: Date?
        let summary: String
        let temperature: Double
        let symbol: String
        let isDaytime: Bool
        let aqi: Double
    }
    
    let city: String
    let region: String
    let updatedAt: Date
    let condition: Condition
    let days: [Day]
    let hours: [Hour]
    let sunrise: Date?
    let sunset: Date?
}

final class HomepageWeatherService {
    static let shared = HomepageWeatherService()
    
    private enum Endpoint {
        static let feed = "https://assets.msn.cn/service/news/feed/pages/weblayout"
        static let hourly = "https://www.msn.cn/zh-cn/weather/hourlyforecast/in-"
        static let provider = "0QfOX3Vn51YCzitbLaRkTTBadtWpgTN8NZLW0C1SEM"
        static let profile = "m-13A1CAFD74C4677709ACDC3875B96665"
        static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    }
    
    private let session: URLSession
    private var isFetching = false
    
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }
    
    var isBusy: Bool {
        return isFetching
    }
    
    func load(completion: @escaping (HomepageWeatherSnapshot?) -> Void) {
        guard !isFetching else {
            return
        }
        
        isFetching = true
        requestFeed { [weak self] result in
            guard let self = self else {
                return
            }
            
            guard let result = result else {
                self.isFetching = false
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            self.requestHours(latitude: result.latitude, longitude: result.longitude) { hours in
                self.isFetching = false
                let snapshot = HomepageWeatherSnapshot(
                    city: result.city,
                    region: result.region,
                    updatedAt: Date(),
                    condition: result.condition,
                    days: result.days,
                    hours: hours,
                    sunrise: result.sunrise,
                    sunset: result.sunset
                )
                DispatchQueue.main.async {
                    completion(snapshot)
                }
            }
        }
    }
    
    // MARK: - Feed
    
    private struct FeedResult {
        let city: String
        let region: String
        let latitude: Double
        let longitude: Double
        let condition: HomepageWeatherSnapshot.Condition
        let days: [HomepageWeatherSnapshot.Day]
        let sunrise: Date?
        let sunset: Date?
    }
    
    private func requestFeed(completion: @escaping (FeedResult?) -> Void) {
        guard let url = feedURL() else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(Endpoint.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        
        let task = session.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(nil)
                return
            }
            
            completion(self.parseFeed(payload))
        }
        task.resume()
    }
    
    private func feedURL() -> URL? {
        var components = URLComponents(string: Endpoint.feed)
        components?.queryItems = [
            URLQueryItem(name: "User", value: Endpoint.profile),
            URLQueryItem(name: "activityId", value: UUID().uuidString),
            URLQueryItem(name: "apikey", value: Endpoint.provider),
            URLQueryItem(name: "audienceMode", value: "adult"),
            URLQueryItem(name: "cm", value: "zh-cn"),
            URLQueryItem(name: "it", value: "edgeid"),
            URLQueryItem(name: "ocid", value: "hponeservicefeed"),
            URLQueryItem(name: "column", value: "c2"),
            URLQueryItem(name: "colwidth", value: "300"),
            URLQueryItem(name: "contentType", value: "article,video,slideshow,webcontent"),
            URLQueryItem(name: "newsTop", value: "48"),
            URLQueryItem(name: "newsSkip", value: "0"),
        ]
        return components?.url
    }
    
    private func parseFeed(_ payload: [String: Any]) -> FeedResult? {
        guard let sections = payload["sections"] as? [[String: Any]] else {
            return nil
        }
        
        for section in sections {
            guard let cards = section["cards"] as? [[String: Any]] else {
                continue
            }
            
            for card in cards where (card["type"] as? String) == "WeatherSummary" {
                guard let payloadText = card["data"] as? String,
                      let data = payloadText.data(using: .utf8),
                      let weatherPayload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    continue
                }
                
                if let result = parseWeatherPayload(weatherPayload) {
                    return result
                }
            }
        }
        
        return nil
    }
    
    private func parseWeatherPayload(_ payload: [String: Any]) -> FeedResult? {
        guard let responses = payload["responses"] as? [[String: Any]],
              let response = responses.first,
              let weatherList = response["weather"] as? [[String: Any]],
              let weather = weatherList.first,
              let current = weather["current"] as? [String: Any] else {
            return nil
        }
        
        let profile = payload["userProfile"] as? [String: Any]
        let detected = profile?["detectedLocation"] as? [String: Any]
        let fallback = profile?["location"] as? [String: Any]
        let city = self.string(detected?["City"]) ?? self.string(fallback?["City"]) ?? ""
        let region = self.string(detected?["State"]) ?? self.string(fallback?["State"]) ?? ""
        
        let source = response["source"] as? [String: Any]
        let coordinates = source?["coordinates"] as? [String: Any]
        let latitude = self.number(coordinates?["lat"])
        let longitude = self.number(coordinates?["lon"])
        
        let symbol = self.string(current["symbol"]) ?? ""
        let condition = HomepageWeatherSnapshot.Condition(
            temperature: self.number(current["temp"]) ?? 0,
            feelsLike: self.number(current["feels"]) ?? 0,
            summary: self.string(current["cap"]) ?? "",
            symbol: symbol,
            isDaytime: (self.string(current["daytime"]) ?? "d") != "n",
            humidity: self.number(current["rh"]) ?? 0,
            windSpeed: self.number(current["windSpd"]) ?? 0,
            windSummary: self.string(current["pvdrWindDir"]) ?? "",
            pressure: self.number(current["baro"]) ?? 0,
            uvIndex: self.number(current["uv"]) ?? 0,
            uvSummary: self.string(current["uvDesc"]) ?? "",
            aqi: self.number(current["aqi"]) ?? 0,
            aqiSeverity: self.string(current["aqiSeverity"]) ?? ""
        )
        
        var days: [HomepageWeatherSnapshot.Day] = []
        var sunrise: Date?
        var sunset: Date?
        if let forecast = weather["forecast"] as? [String: Any],
           let dayEntries = forecast["days"] as? [[String: Any]] {
            for entry in dayEntries.prefix(10) {
                guard let daily = entry["daily"] as? [String: Any] else {
                    continue
                }
                
                let symbol = self.string(daily["symbol"]) ?? ""
                days.append(HomepageWeatherSnapshot.Day(
                    date: self.date(daily["valid"]),
                    summary: self.string(daily["pvdrCap"]) ?? "",
                    high: self.number(daily["tempHi"]) ?? 0,
                    low: self.number(daily["tempLo"]) ?? 0,
                    symbol: symbol,
                    isDaytime: !symbol.hasPrefix("n"),
                    aqi: self.number(daily["aqi"]) ?? 0
                ))
                
                if let almanac = entry["almanac"] as? [String: Any] {
                    sunrise = self.date(almanac["sunrise"])
                    sunset = self.date(almanac["sunset"])
                }
            }
        }
        
        guard let latitude = latitude, let longitude = longitude else {
            return nil
        }
        
        return FeedResult(
            city: city,
            region: region,
            latitude: latitude,
            longitude: longitude,
            condition: condition,
            days: days,
            sunrise: sunrise,
            sunset: sunset
        )
    }
    
    // MARK: - Hourly
    
    private func requestHours(latitude: Double, longitude: Double, completion: @escaping ([HomepageWeatherSnapshot.Hour]) -> Void) {
        let coordinateText = String(format: "%.4f,%.4f", latitude, longitude)
        guard let url = URL(string: Endpoint.hourly + coordinateText) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(Endpoint.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        
        let task = session.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion([])
                return
            }
            
            completion(self.parseHours(html))
        }
        task.resume()
    }
    
    private func parseHours(_ html: String) -> [HomepageWeatherSnapshot.Hour] {
        guard let state = weatherState(in: html),
              let forecast = state["forecast"] as? [[String: Any]] else {
            return []
        }
        
        var hours: [HomepageWeatherSnapshot.Hour] = []
        for day in forecast {
            guard let entries = day["hourly"] as? [[String: Any]] else {
                continue
            }
            
            for entry in entries {
                let symbol = self.string(entry["symbol"]) ?? ""
                hours.append(HomepageWeatherSnapshot.Hour(
                    date: self.date(entry["timeStr"]),
                    summary: self.string(entry["cap"]) ?? "",
                    temperature: self.number(entry["temperature"]) ?? 0,
                    symbol: symbol,
                    isDaytime: !symbol.hasPrefix("n"),
                    aqi: self.number(entry["aqi"]) ?? 0
                ))
                if hours.count >= 24 {
                    return hours
                }
            }
        }
        
        return hours
    }
    
    private func weatherState(in html: String) -> [String: Any]? {
        guard let expression = try? NSRegularExpression(
            pattern: "<script[^>]*>([\\s\\S]*?)</script>",
            options: []
        ) else {
            return nil
        }
        
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = expression.matches(in: html, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges > 1,
                  let scriptRange = Range(match.range(at: 1), in: html) else {
                continue
            }
            
            let script = String(html[scriptRange])
            guard script.contains("WeatherData"), script.contains("forecast") else {
                continue
            }
            
            guard let object = self.firstJSONObject(in: script) as? [String: Any],
                  let weatherData = object["WeatherData"] as? [String: Any],
                  let state = weatherData["_@STATE@_"] as? [String: Any] else {
                continue
            }
            
            return state
        }
        
        return nil
    }
    
    private func firstJSONObject(in text: String) -> Any? {
        let bytes = Array(text.utf8)
        guard let start = bytes.firstIndex(of: UInt8(ascii: "{")) else {
            return nil
        }
        
        var depth = 0
        var isInString = false
        var isEscaped = false
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if byte == UInt8(ascii: "\\") {
                    isEscaped = true
                } else if byte == UInt8(ascii: "\"") {
                    isInString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                isInString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 {
                    let slice = bytes[start...index]
                    let json = String(decoding: slice, as: UTF8.self)
                    return try? JSONSerialization.jsonObject(with: Data(json.utf8))
                }
            }
            index += 1
        }
        
        return nil
    }
    
    // MARK: - Helpers
    
    private func string(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }
    
    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }
    
    private func date(_ value: Any?) -> Date? {
        guard let text = value as? String else {
            return nil
        }
        
        if let date = HomepageWeatherService.fractionalFormatter.date(from: text) {
            return date
        }
        return HomepageWeatherService.plainFormatter.date(from: text)
    }
    
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
