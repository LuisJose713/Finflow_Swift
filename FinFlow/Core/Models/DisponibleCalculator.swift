import Foundation

/// Read-only estimate in COP. No future income or recurring obligations are
/// inferred; such projections would risk double-counting planned expenses.
struct DisponibleSnapshot {
    let balance: Decimal
    let pending: Decimal
    let reserved: Decimal
    let available: Decimal
    let dailyAllowance: Decimal
    let days: Int
    let pendingCount: Int
    let missingDateCount: Int
}

enum DisponibleCalculator {
    private static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite, abs(value) <= 1_000_000_000_000 else { return nil }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
    }

    static func calculate(
        accounts: [FinancialAccount],
        expenses: [PlannedExpense],
        reserve: Decimal,
        payday: Date,
        today: Date = .now
    ) -> DisponibleSnapshot? {
        guard reserve >= 0, reserve <= Decimal(1_000_000_000_000) else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: payday)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day,
              days > 0, days <= 366 else { return nil }

        var balance = Decimal.zero
        for account in accounts where !account.archived && account.currency.uppercased() == "COP" {
            guard let amount = decimal(account.balance) else { return nil }
            balance += amount
        }

        var pending = Decimal.zero
        var pendingCount = 0
        var missingDates = 0
        for expense in expenses where expense.status.lowercased() == "pending" {
            guard let dueDate = expense.parsedDueDate else {
                missingDates += 1
                continue
            }
            // The next payday is the start of the following period.
            guard calendar.startOfDay(for: dueDate) < end else { continue }
            guard let amount = decimal(expense.amount), amount >= 0 else { return nil }
            pending += amount
            pendingCount += 1
        }

        let available = balance - pending - reserve
        var rawDaily = max(available, Decimal.zero) / Decimal(days)
        var roundedDaily = Decimal.zero
        NSDecimalRound(&roundedDaily, &rawDaily, 2, .down)
        return DisponibleSnapshot(balance: balance, pending: pending,
                                  reserved: reserve, available: available,
                                  dailyAllowance: roundedDaily, days: days,
                                  pendingCount: pendingCount,
                                  missingDateCount: missingDates)
    }
}
