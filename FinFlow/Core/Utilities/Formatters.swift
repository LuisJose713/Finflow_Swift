import Foundation

extension BinaryInteger {
    var cop: String { CurrencyFormatter.format(Double(self)) }
}

enum CurrencyFormatter {
    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_CO")
        formatter.numberStyle = .currency
        formatter.currencyCode = "COP"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
    static func compact(_ value: Double) -> String {
        if abs(value) >= 1_000_000 { return String(format: "$%.1f M", value / 1_000_000) }
        if abs(value) >= 1_000 { return String(format: "$%.1f K", value / 1_000) }
        return format(value)
    }
}

enum DateFormatters {
    // Return a fresh formatter per access; DateFormatter is mutable and not thread-safe.
    static var display: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_CO"); f.dateStyle = .medium; return f
    }
    static var isoDay: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0); return f
    }
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let localDateTime = DateFormatter()
        localDateTime.locale = Locale(identifier: "en_US_POSIX")
        localDateTime.timeZone = TimeZone.current
        localDateTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = localDateTime.date(from: value) { return date }
        localDateTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = localDateTime.date(from: value) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: String(value.prefix(10)))
    }
}
