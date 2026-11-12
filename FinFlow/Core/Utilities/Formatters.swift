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
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
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


/// Canonical decimal dots in the model; Colombian separators in the field.
enum COPInput {
    static func normalize(_ input: String, previous: String = "") -> String? {
        let raw = input.replacingOccurrences(of: "COP", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "$", with: "").filter { !$0.isWhitespace }
        if raw.isEmpty { return "" }
        guard raw.allSatisfy({ "0123456789.,".contains($0) }), raw.filter({ $0 == "," }).count <= 1 else { return nil }
        let commas = raw.firstIndex(of: ",")
        let dots = raw.filter { $0 == "." }.count
        var separator = commas
        if commas == nil, dots == 1, let dot = raw.firstIndex(of: ".") {
            let fractionSize = raw.distance(from: raw.index(after: dot), to: raw.endIndex)
            let editingDecimal = previous.contains(".") && abs(input.count - previous.count) <= 1
            if fractionSize <= 2 || editingDecimal { separator = dot }
        }
        let wholeText = separator.map { String(raw[..<$0]) } ?? raw
        if wholeText.contains(".") {
            guard wholeText.range(of: #"^[0-9]{1,3}(\.[0-9]{3})+$"#, options: .regularExpression) != nil else { return nil }
        }
        let stripped = wholeText.replacingOccurrences(of: ".", with: "").drop(while: { $0 == "0" })
        let whole = stripped.isEmpty ? "0" : String(stripped)
        let fraction = separator.map { String(raw[raw.index(after: $0)...]) } ?? ""
        guard fraction.count <= 2, fraction.allSatisfy({ "0123456789".contains($0) }), whole.count <= 13 else { return nil }
        let normalized = whole + (separator == nil ? "" : "." + fraction)
        guard let value = Double(normalized), value.isFinite, value <= 1_000_000_000_000 else { return nil }
        return normalized
    }

    static func display(_ raw: String, padDecimals: Bool) -> String {
        guard !raw.isEmpty else { return "" }
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = Array(parts[0])
        var result = ""
        for (index, digit) in whole.enumerated() {
            if index > 0 && (whole.count - index) % 3 == 0 { result += "." }
            result.append(digit)
        }
        if parts.count == 2 {
            let fraction = String(parts[1])
            result += "," + fraction + (padDecimals ? String(repeating: "0", count: max(0, 2 - fraction.count)) : "")
        } else if padDecimals { result += ",00" }
        return result
    }
}
