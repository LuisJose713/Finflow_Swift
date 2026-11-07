import Foundation

// Small non-network test doubles that match the fields consumed by the engine.
struct FinancialAccount {
    let balance: Double
    let currency: String
    let archived: Bool
}
struct PlannedExpense {
    let amount: Double
    let status: String
    let dueDate: String?
    var parsedDueDate: Date? {
        guard let dueDate else { return nil }
        return TestClock.date(dueDate)
    }
}
enum TestClock {
    static func date(_ value: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: value)
    }
}
@main
struct DisponibleCalculatorSmoke {
    static func main() {
        guard let today = TestClock.date("2026-11-07"),
              let payday = TestClock.date("2026-11-22") else {
            fatalError("Could not initialize test calendar")
        }
        let accounts = [
            FinancialAccount(balance: 1_200_000, currency: "COP", archived: false),
            FinancialAccount(balance: 100_000, currency: "USD", archived: false),
            FinancialAccount(balance: 800_000, currency: "COP", archived: true)
        ]
        let expenses = [
            PlannedExpense(amount: 300_000, status: "pending", dueDate: "2026-11-09"),
            PlannedExpense(amount: 100_000, status: "done", dueDate: "2026-11-13"),
            PlannedExpense(amount: 80_000, status: "pending", dueDate: "2026-11-30"),
            PlannedExpense(amount: 11_000, status: "pending", dueDate: nil)
        ]
        guard let result = DisponibleCalculator.calculate(
            accounts: accounts, expenses: expenses, reserve: Decimal(200_000),
            payday: payday, today: today) else {
            fatalError("Expected a valid estimate")
        }
        assert(result.balance == Decimal(1_200_000), "Only active COP accounts count")
        assert(result.pending == Decimal(300_000), "Only due pending expenses count")
        assert(result.available == Decimal(700_000), "Balance minus obligations minus reserve")
        assert(result.days == 15, "Correct period length")
        assert(result.dailyAllowance == Decimal(string: "46666.66"), "Daily allowance floors cents")
        assert(result.missingDateCount == 1, "Pending payments without date are flagged")
        assert(DisponibleCalculator.calculate(
            accounts: accounts, expenses: expenses, reserve: Decimal(-1),
            payday: payday, today: today) == nil, "Negative reserve rejected")
        assert(DisponibleCalculator.calculate(
            accounts: accounts, expenses: expenses, reserve: .zero,
            payday: today, today: today) == nil, "Payday must be in the future")

        let overdue = [PlannedExpense(amount: 1_500_000, status: "pending", dueDate: "2026-11-01")]
        guard let deficit = DisponibleCalculator.calculate(accounts: accounts, expenses: overdue,
                   reserve: .zero, payday: payday, today: today) else {
            fatalError("Expected deficit")
        }
        assert(deficit.available == Decimal(-300_000), "Overdue obligations are included")
        assert(deficit.dailyAllowance == .zero, "No negative spending allowance")
        print("FINFLOW DISPONIBLE: 11 financial assertions passed")
    }
}
