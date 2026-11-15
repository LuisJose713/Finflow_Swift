import Foundation

extension BinaryInteger {
    var cop: String { CurrencyFormatter.format(Double(self)) }
}

enum CurrencyFormatter {
    static let available: [(String, String)] = [
        ("COP", "Peso colombiano"), ("USD", "Dólar estadounidense"),
        ("EUR", "Euro"), ("GBP", "Libra esterlina"),
        ("MXN", "Peso mexicano"), ("BRL", "Real brasileño"),
        ("CAD", "Dólar canadiense")
    ]

    private static let selectionKey = "finflow.displayCurrency.code"
    private static let quoteKey = "finflow.displayCurrency.quote"
    private static let revisionKey = "finflow.displayCurrency.revision"
    private static let accountKey = "finflow.displayCurrency.activeAccount"


    struct ExchangeQuote: Codable {
        let code: String
        let rate: Double
        let date: String
        let fetchedAt: TimeInterval
    }

    private struct RemoteExchangeQuote: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Double
    }

    enum ExchangeError: Error, LocalizedError {
        case invalid
        var errorDescription: String? { "No hay una tasa de referencia verificable. Se conserva la moneda anterior." }
    }

    static var preferredCode: String {
        let code = UserDefaults.standard.string(forKey: selectionKey) ?? "COP"
        return available.contains(where: { $0.0 == code }) ? code : "COP"
    }

    private static func currentQuote() -> ExchangeQuote? {
        guard preferredCode != "COP",
              let data = UserDefaults.standard.data(forKey: quoteKey),
              let quote = try? JSONDecoder().decode(ExchangeQuote.self, from: data),
              quote.code == preferredCode,
              quote.rate > 0, quote.rate.isFinite, quote.rate < 1000,
              quote.fetchedAt <= Date().timeIntervalSince1970,
              Date().timeIntervalSince1970 - quote.fetchedAt < 72 * 3600,
              let effectiveDate = ISO8601DateFormatter().date(from: quote.date + "T00:00:00Z"),
              abs(effectiveDate.timeIntervalSinceNow) < 14 * 86400
        else { return nil }
        return quote
    }

    static var displayCode: String { currentQuote()?.code ?? "COP" }
    static var rateDate: String? { currentQuote()?.date }

    /// Presentation only. The backend, inputs and exported statements retain their source COP.
    static func convertedAmountFromCOP(_ value: Double, rate: Double) -> Double? {
        guard value.isFinite, rate.isFinite, rate > 0 else { return nil }
        let result = value * rate
        return result.isFinite ? result : nil
    }

    private static func presented(_ value: Double) -> (Double, String) {
        guard let quote = currentQuote(),
              let converted = convertedAmountFromCOP(value, rate: quote.rate) else { return (value, "COP") }
        return (converted, quote.code)
    }

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let (amount, code) = presented(value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_CO")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        if code == "COP" {
            formatter.numberStyle = .currency
            formatter.currencyCode = "COP"
            return formatter.string(from: NSNumber(value: amount)) ?? String(format: "COP %.2f", amount)
        }
        formatter.numberStyle = .decimal
        return code + " " + (formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
    }

    static func compact(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let (amount, code) = presented(value)
        if abs(amount) >= 1_000_000 { return String(format: "%@ %.1f M", code, amount / 1_000_000) }
        if abs(amount) >= 1_000 { return String(format: "%@ %.1f K", code, amount / 1_000) }
        return format(value)
    }

    static func fetchVerifiedQuote(_ code: String) async throws -> ExchangeQuote {
        guard let url = URL(string: "https://api.frankfurter.dev/v2/rate/cop/" + code.lowercased()) else {
            throw ExchangeError.invalid
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let status = response as? HTTPURLResponse, status.statusCode == 200,
              let remote = try? JSONDecoder().decode(RemoteExchangeQuote.self, from: data),
              remote.base.uppercased() == "COP", remote.quote.uppercased() == code,
              remote.rate.isFinite, remote.rate > 0, remote.rate < 1000,
              let effectiveDate = ISO8601DateFormatter().date(from: remote.date + "T00:00:00Z"),
              abs(effectiveDate.timeIntervalSinceNow) < 14 * 86400
        else { throw ExchangeError.invalid }
        return ExchangeQuote(code: code, rate: remote.rate, date: remote.date,
                             fetchedAt: Date().timeIntervalSince1970)
    }

    static var accountOwner: Int { UserDefaults.standard.integer(forKey: accountKey) }

    static func beginAccount(_ id: Int?) {
        UserDefaults.standard.set(id ?? 0, forKey: accountKey)
        UserDefaults.standard.set("COP", forKey: selectionKey)
        UserDefaults.standard.removeObject(forKey: quoteKey)
        incrementRevision()
    }

    static func applyServerCode(_ code: String, quote: ExchangeQuote?) throws {
        guard available.contains(where: { $0.0 == code }),
              (code == "COP" && quote == nil) || (quote?.code == code) else { throw ExchangeError.invalid }
        if let quote {
            UserDefaults.standard.set(try JSONEncoder().encode(quote), forKey: quoteKey)
        } else {
            UserDefaults.standard.removeObject(forKey: quoteKey)
        }
        UserDefaults.standard.set(code, forKey: selectionKey)
        incrementRevision()
    }

    private static func incrementRevision() {
        let current = UserDefaults.standard.integer(forKey: revisionKey)
        UserDefaults.standard.set(current == Int.max ? 1 : current + 1, forKey: revisionKey)
    }
}

enum DateFormatters {
    // Return a fresh formatter per access; DateFormatter is mutable and not thread-safe.
    static var display: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_CO"); f.dateStyle = .medium; return f
    }
    static var isoDay: DateFormatter {
        calendarDayFormatter(in: .current)
    }
    // A movement/deadline is a calendar day chosen in the device's time zone,
    // not a UTC instant. UTC would move evening entries to tomorrow in Colombia.
    static func calendarDayFormatter(in timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        return f
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
        var raw = input.replacingOccurrences(of: "COP", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "$", with: "").filter { !$0.isWhitespace }
        if raw.isEmpty { return "" }
        guard raw.allSatisfy({ "0123456789.,".contains($0) }), raw.filter({ $0 == "," }).count <= 1 else { return nil }
        let previousDisplay = display(previous, padDecimals: false)
        let editingWhole = !previous.contains(".") && previousDisplay.contains(".") &&
            abs(input.count - previousDisplay.count) <= 1 && !raw.contains(",") && !raw.hasSuffix(".")
        if editingWhole { raw = raw.replacingOccurrences(of: ".", with: "") }
        let commas = raw.firstIndex(of: ",")
        let dots = raw.filter { $0 == "." }.count
        var separator = commas
        if commas == nil, let dot = raw.lastIndex(of: ".") {
            let fractionSize = raw.distance(from: raw.index(after: dot), to: raw.endIndex)
            let editingDecimal = dots == 1 && previous.contains(".") && abs(input.count - previous.count) <= 1
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
