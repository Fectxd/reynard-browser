//
//  HomepageWeatherStyle.swift
//  Reynard
//
//  Shared formatting and SF Symbol mapping for the weather surfaces.
//

import UIKit

enum HomepageWeatherStyle {
    static func temperature(_ value: Double) -> String {
        return "\(Int(value.rounded()))°"
    }
    
    static func range(high: Double, low: Double) -> String {
        return "\(Int(high.rounded()))° / \(Int(low.rounded()))°"
    }
    
    static func imageName(symbol: String, summary: String, isDaytime: Bool) -> String {
        let isNight = !isDaytime || symbol.hasPrefix("n")
        let text = summary.lowercased()
        let original = summary
        
        if original.contains("雷") || text.contains("thunder") || text.contains("storm") {
            return "cloud.bolt.rain.fill"
        }
        if original.contains("雪") || original.contains("冰") || text.contains("snow") || text.contains("sleet") {
            return "snowflake"
        }
        if original.contains("雨") || text.contains("rain") || text.contains("shower") || text.contains("drizzle") {
            return "cloud.rain.fill"
        }
        if original.contains("雾") || original.contains("霾") || original.contains("沙") || original.contains("尘")
            || text.contains("fog") || text.contains("haze") || text.contains("dust") {
            return "cloud.fog.fill"
        }
        if original.contains("风") || text.contains("wind") {
            return "wind"
        }
        if original.contains("阴") || text.contains("cloudy") || text.contains("overcast") {
            return "cloud.fill"
        }
        if original.contains("多云") || original.contains("局部") || original.contains("少云")
            || text.contains("partly") || text.contains("mostly") {
            return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        }
        if original.contains("晴") || original.contains("阳光") || text.contains("sun") || text.contains("clear") {
            return isNight ? "moon.stars.fill" : "sun.max.fill"
        }
        
        return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
    }
    
    static func dayLabel(for date: Date?, index: Int) -> String {
        switch index {
        case 0:
            return NSLocalizedString("Today", comment: "Weather forecast day")
        case 1:
            return NSLocalizedString("Tomorrow", comment: "Weather forecast day")
        default:
            break
        }
        
        guard let date = date else {
            return ""
        }
        
        let weekday = calendar.component(.weekday, from: date)
        let names = [
            NSLocalizedString("Sunday", comment: "Weekday"),
            NSLocalizedString("Monday", comment: "Weekday"),
            NSLocalizedString("Tuesday", comment: "Weekday"),
            NSLocalizedString("Wednesday", comment: "Weekday"),
            NSLocalizedString("Thursday", comment: "Weekday"),
            NSLocalizedString("Friday", comment: "Weekday"),
            NSLocalizedString("Saturday", comment: "Weekday"),
        ]
        guard (1...7).contains(weekday) else {
            return ""
        }
        return names[weekday - 1]
    }
    
    static func hourLabel(for date: Date?, isCurrentHour: Bool) -> String {
        guard !isCurrentHour else {
            return NSLocalizedString("Now", comment: "Weather forecast hour")
        }
        
        guard let date = date else {
            return ""
        }
        
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
    
    static func timeLabel(for date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    static func currentHourIndex(hours: [HomepageWeatherSnapshot.Hour]) -> Int {
        let now = Date()
        guard let index = hours.firstIndex(where: { hour in
            guard let date = hour.date else {
                return false
            }
            return date.addingTimeInterval(1800) > now
        }) else {
            return 0
        }
        return index
    }
    
    private static var calendar: Calendar {
        return Calendar.current
    }
}
