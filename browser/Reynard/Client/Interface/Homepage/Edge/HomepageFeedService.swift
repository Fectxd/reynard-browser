//
//  HomepageFeedService.swift
//  Reynard
//
//  MSN news feed used by the homepage information panel.
//

import UIKit

struct HomepageFeedArticle {
    let title: String
    let url: URL
    let provider: String
    let imageURL: URL?
    let publishedAt: Date?
}

final class HomepageFeedService {
    static let shared = HomepageFeedService()
    
    private enum Endpoint {
        static let feed = "https://assets.msn.cn/service/news/feed/pages/weblayout"
        static let provider = "0QfOX3Vn51YCzitbLaRkTTBadtWpgTN8NZLW0C1SEM"
        static let profile = "m-13A1CAFD74C4677709ACDC3875B96665"
        static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    }
    
    private let session: URLSession
    private var isFetching = false
    
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }
    
    func load(completion: @escaping ([HomepageFeedArticle]) -> Void) {
        guard !isFetching, let url = feedURL() else {
            completion([])
            return
        }
        
        isFetching = true
        var request = URLRequest(url: url)
        request.setValue(Endpoint.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        
        let task = session.dataTask(with: request) { [weak self] data, _, _ in
            self?.isFetching = false
            guard let data = data,
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            let articles = HomepageFeedService.parseArticles(payload)
            DispatchQueue.main.async {
                completion(articles)
            }
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
    
    private static func parseArticles(_ payload: [String: Any]) -> [HomepageFeedArticle] {
        guard let sections = payload["sections"] as? [[String: Any]] else {
            return []
        }
        
        var articles: [HomepageFeedArticle] = []
        var seen = Set<String>()
        for section in sections {
            guard let cards = section["cards"] as? [[String: Any]] else {
                continue
            }
            
            for card in cards {
                guard let type = card["type"] as? String,
                      type == "article" || type == "webcontent" || type == "video" || type == "slideshow",
                      let title = card["title"] as? String,
                      !title.isEmpty,
                      let urlText = card["url"] as? String,
                      let url = URL(string: urlText),
                      !seen.contains(urlText) else {
                    continue
                }
                
                seen.insert(urlText)
                let provider = (card["provider"] as? [String: Any])?["name"] as? String ?? ""
                var imageURL: URL?
                if let images = card["images"] as? [[String: Any]],
                   let first = images.first,
                   let imageText = first["url"] as? String {
                    imageURL = URL(string: imageText)
                }
                
                var publishedAt: Date?
                if let published = card["publishedDateTime"] as? String {
                    publishedAt = HomepageFeedService.date(from: published)
                }
                
                articles.append(HomepageFeedArticle(
                    title: title,
                    url: url,
                    provider: provider,
                    imageURL: imageURL,
                    publishedAt: publishedAt
                ))
                
                if articles.count >= 40 {
                    return articles
                }
            }
        }
        
        return articles
    }
    
    private static func date(from text: String) -> Date? {
        if let date = fractionalFormatter.date(from: text) {
            return date
        }
        return plainFormatter.date(from: text)
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

final class HomepageFeedImageLoader {
    static let shared = HomepageFeedImageLoader()
    
    private let session: URLSession
    private let cache = NSCache<NSURL, UIImage>()
    
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        cache.countLimit = 80
    }
    
    func image(for url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            self?.cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async {
                completion(image)
            }
        }
        task.resume()
    }
}
