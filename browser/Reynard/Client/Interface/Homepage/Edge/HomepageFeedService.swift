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
    private var pendingCompletions: [([HomepageFeedArticle]) -> Void] = []
    
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }
    
    /// Always calls back on the main queue. Concurrent requests share one fetch.
    func load(completion: @escaping ([HomepageFeedArticle]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingCompletions.append(completion)
        guard pendingCompletions.count == 1 else {
            return
        }
        
        guard let url = feedURL() else {
            finish(with: [])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(Endpoint.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        let task = session.dataTask(with: request) { [weak self] data, _, _ in
            let payload = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let articles = payload.map(HomepageFeedService.parseArticles) ?? []
            DispatchQueue.main.async { [weak self] in
                self?.finish(with: articles)
            }
        }
        task.resume()
    }
    
    private func finish(with articles: [HomepageFeedArticle]) {
        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0(articles) }
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
            URLQueryItem(name: "contentType", value: "article,video,slideshow"),
            URLQueryItem(name: "newsTop", value: "48"),
            URLQueryItem(name: "newsSkip", value: "0"),
        ]
        return components?.url
    }
    
    private static let maximumArticleCount = 60
    private static let contentTypes: Set<String> = ["article", "video", "slideshow"]
    
    /// MSN nests cards at varying depths (sections[].subSections[].cards[],
    /// cards[].subCards[], ...), so walk the whole payload and keep every
    /// content card, skipping ads and sponsored placements.
    private static func parseArticles(_ payload: [String: Any]) -> [HomepageFeedArticle] {
        var articles: [HomepageFeedArticle] = []
        var seen = Set<String>()
        collectArticles(from: payload, into: &articles, seen: &seen)
        return articles
    }
    
    private static func collectArticles(from node: Any, into articles: inout [HomepageFeedArticle], seen: inout Set<String>) {
        guard articles.count < maximumArticleCount else {
            return
        }
        
        if let list = node as? [Any] {
            for item in list {
                collectArticles(from: item, into: &articles, seen: &seen)
            }
            return
        }
        
        guard let card = node as? [String: Any] else {
            return
        }
        
        if let article = article(from: card), !seen.contains(article.url.absoluteString) {
            seen.insert(article.url.absoluteString)
            articles.append(article)
        }
        
        for key in ["sections", "subSections", "cards", "subCards", "regions"] {
            if let child = card[key] {
                collectArticles(from: child, into: &articles, seen: &seen)
            }
        }
    }
    
    private static func article(from card: [String: Any]) -> HomepageFeedArticle? {
        guard let type = card["type"] as? String,
              contentTypes.contains(type.lowercased()),
              !isAdvertisement(card),
              let title = (card["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              let urlText = card["url"] as? String,
              let url = URL(string: urlText) ?? URL(string: urlText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        
        let provider = (card["provider"] as? [String: Any])?["name"] as? String ?? ""
        var imageURL: URL?
        if let images = card["images"] as? [[String: Any]],
           let imageText = images.first?["url"] as? String {
            imageURL = URL(string: imageText)
        }
        
        var publishedAt: Date?
        if let published = card["publishedDateTime"] as? String {
            publishedAt = date(from: published)
        }
        
        return HomepageFeedArticle(title: title, url: url, provider: provider, imageURL: imageURL, publishedAt: publishedAt)
    }
    
    // MARK: - Ad Filtering
    
    private static let adMarkers = ["nativead", "native_ad", "sponsored", "advert", "promoted", "adslot", "taboola", "outbrain"]
    private static let adProviderMarkers = ["广告", "推广", "赞助", "sponsored", "advertisement", "promoted"]
    private static let adHostPrefixes = ["ad.", "ads.", "adserver.", "clk.", "click.", "track."]
    private static let adDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "taboola.com",
        "outbrain.com", "adnxs.com", "criteo.com", "criteo.net", "amazon-adsystem.com",
    ]
    
    static func isAdvertisement(_ card: [String: Any]) -> Bool {
        let type = (card["type"] as? String ?? "").lowercased()
        if adMarkers.contains(where: { type.contains($0) }) || type == "ad" {
            return true
        }
        
        for key in ["isSponsored", "sponsored", "isAd", "isNativeAd", "isPromoted"] {
            if let flag = card[key] as? Bool, flag { return true }
            if let flag = card[key] as? String, flag.lowercased() == "true" { return true }
        }
        if card["adId"] != nil || card["nativeAd"] != nil || card["adMetadata"] != nil {
            return true
        }
        
        let provider = card["provider"] as? [String: Any]
        let providerName = (provider?["name"] as? String ?? "").lowercased()
        if adProviderMarkers.contains(where: { providerName.contains($0) }) {
            return true
        }
        
        let source = (card["source"] as? String ?? "").lowercased()
        if adMarkers.contains(where: { source.contains($0) }) {
            return true
        }
        
        if let urlText = card["url"] as? String,
           let components = URLComponents(string: urlText),
           let host = components.host?.lowercased() {
            if adHostPrefixes.contains(where: { host.hasPrefix($0) }) ||
                adDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) ||
                components.path.lowercased().contains("/aclk") {
                return true
            }
        }
        
        return false
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
