import Foundation

struct AppUser: Codable, Identifiable, Sendable {
    let id: Int
    let email: String
    let name: String
    var avatar: String? = nil
    var currency: String = "COP"
    var theme: String = "system"
    var role: String = "USER"
    var isAdmin: Bool { role == "ADMIN" }

    enum CodingKeys: String, CodingKey { case id, email, name, avatar, currency, theme, role }

    init(id: Int, email: String, name: String, avatar: String? = nil, currency: String = "COP", theme: String = "system", role: String = "USER") {
        self.id = id; self.email = email; self.name = name
        self.avatar = avatar; self.currency = currency; self.theme = theme; self.role = role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        name = try c.decode(String.self, forKey: .name)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "COP"
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "USER"
    }
}

struct AuthResponse: Decodable, Sendable { let token: String; let user: AppUser; let refreshToken: String? }
struct LoginRequest: Encodable { let email: String; let password: String }
struct RegisterRequest: Encodable {
    let name: String
    let email: String
    let password: String
    let privacyAccepted: Bool?
    let privacyVersion: String?
    let marketingConsent: Bool?

    init(name: String, email: String, password: String,
         privacyAccepted: Bool? = nil, privacyVersion: String? = nil,
         marketingConsent: Bool? = nil) {
        self.name = name
        self.email = email
        self.password = password
        self.privacyAccepted = privacyAccepted
        self.privacyVersion = privacyVersion
        self.marketingConsent = marketingConsent
    }
}

// These models mirror the active Railway privacy API. A modal dismissal
// must never be serialized as consent; only the server can issue a receipt.
struct PrivacyPolicy: Decodable {
    let version: String
    let ready: Bool
    let effectiveDate: String
    let controllerName: String
    let controllerNit: String?
    let contactEmail: String
    let contactAddress: String
    let contactPhone: String
}

struct PrivacyStatus: Decodable {
    let accepted: Bool
    let version: String
    let policyReady: Bool
    let marketingConsent: Bool
    let acceptedAt: String?
}

struct PrivacyConsentInput: Encodable {
    let accepted: Bool
    let policyVersion: String
    let marketingConsent: Bool
}

struct PrivacyConsentResponse: Decodable {
    let accepted: Bool
    let version: String
}

struct PrivacyMarketingInput: Encodable { let marketingConsent: Bool }
struct PrivacyMarketingResponse: Decodable {
    let marketingConsent: Bool
    let saved: Bool
}

struct PrivacyRightsInput: Encodable {
    let type: String
    let description: String
}
struct PrivacyRightsResponse: Decodable {
    let id: Int
    let status: String
    let message: String
}
struct PrivacyRightRecord: Decodable, Identifiable {
    let id: Int
    let requestType: String
    let status: String
    let createdAt: String?
    let description: String?
    enum CodingKeys: String, CodingKey {
        case id, status, description
        case requestType = "request_type"
        case createdAt = "created_at"
    }
}
struct PrivacyReceipt: Decodable { let consents: [PrivacyConsentRecord] }
struct PrivacyConsentRecord: Decodable, Identifiable {
    let policyVersion: String
    let marketingOptIn: Bool
    let acceptedAt: String
    let source: String
    var id: String { policyVersion + ":" + acceptedAt }
    enum CodingKeys: String, CodingKey {
        case source
        case policyVersion = "policy_version"
        case marketingOptIn = "marketing_opt_in"
        case acceptedAt = "accepted_at"
    }
}


/// Mirrors the Transaction entity returned by the Spring Boot API.
struct FinanceTransaction: Codable, Identifiable {
    var id: Int
    var description: String
    var amount: Double
    var type: String
    var categoryId: Int = 0
    var accountId: Int? = nil
    var date: String?
    var createdAt: String?
    var notes: String? // Kept for local/offline compatibility; backend Transaction has no notes field.
    var currency: String?
    var status: String?
    var userId: Int?

    enum CodingKeys: String, CodingKey { case id, description, amount, type, categoryId, accountId, date, createdAt, notes, currency, status, userId }

    init(id: Int, description: String, amount: Double, type: String, categoryId: Int = 0, accountId: Int? = nil, date: String? = nil, createdAt: String? = nil, notes: String? = nil, currency: String? = nil, status: String? = nil, userId: Int? = nil) {
        self.id = id; self.description = description; self.amount = amount; self.type = type
        self.categoryId = categoryId; self.accountId = accountId; self.date = date; self.createdAt = createdAt
        self.notes = notes; self.currency = currency; self.status = status; self.userId = userId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "expense"
        categoryId = try c.decodeIfPresent(Int.self, forKey: .categoryId) ?? 0
        accountId = try c.decodeIfPresent(Int.self, forKey: .accountId)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        userId = try c.decodeIfPresent(Int.self, forKey: .userId)
    }

    var parsedDate: Date { DateFormatters.parse(date ?? createdAt) ?? .now }
}

/// Fields accepted by TransactionRequest. The backend currently does not persist notes.
struct CreateTransactionRequest: Codable {
    let description: String
    let amount: Double
    let type: String
    let categoryId: Int
    let date: String
    let notes: String?
    var accountId: Int? = nil
    let currency: String = "COP"
    let status: String = "completed"
}

struct TransactionStats: Decodable {
    var totalIncome: Double = 0
    var totalExpenses: Double = 0
    var balance: Double = 0
    var savingsRate: Double = 0
    var monthlyData: [MonthlyData] = []
    var categoryData: [CategoryData] = []
    enum CodingKeys: String, CodingKey { case totalIncome, totalExpenses, balance, savingsRate, monthlyData, categoryData }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalIncome = try c.decodeIfPresent(Double.self, forKey: .totalIncome) ?? 0
        totalExpenses = try c.decodeIfPresent(Double.self, forKey: .totalExpenses) ?? 0
        balance = try c.decodeIfPresent(Double.self, forKey: .balance) ?? totalIncome - totalExpenses
        savingsRate = try c.decodeIfPresent(Double.self, forKey: .savingsRate) ?? 0
        monthlyData = try c.decodeIfPresent([MonthlyData].self, forKey: .monthlyData) ?? []
        categoryData = try c.decodeIfPresent([CategoryData].self, forKey: .categoryData) ?? []
    }
}
struct MonthlyData: Decodable, Identifiable { var month: String; var income: Double; var expenses: Double; var id: String { month } }
struct CategoryData: Decodable, Identifiable { var category: String; var amount: Double; var percentage: Double; var id: String { category } }
struct FinanceCategory: Codable, Identifiable {
    let id: Int
    let name: String
    let type: String
    let userId: Int?
    let createdAt: String?
    var isSystem: Bool { userId == nil }
}
struct CategoryMutation: Encodable {
    let name: String
    let type: String
}

struct BudgetOverview: Decodable, Identifiable {
    let id: Int
    let categoryId: Int
    let categoryName: String
    let year: Int
    let month: Int
    let limitAmount: Double
    let spent: Double
    let remaining: Double
    let percentUsed: Int
    let status: String
    let currency: String
    var progress: Double {
        guard limitAmount > 0 else { return 0 }
        return min(max(spent / limitAmount, 0), 1)
    }
}
struct CreateBudgetRequest: Encodable {
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Double
}
struct UpdateBudgetLimitRequest: Encodable {
    let amount: Double
}

struct AdminOverview: Decodable {
    let users: Int
    let newUsers30Days: Int
    let activeUsers30Days: Int
    let transactions: Int
    let transactions30Days: Int
    let incomeTransactions: Int
    let expenseTransactions: Int
    let goals: Int
    let plannedExpenses: Int
    let pendingExpenses: Int
    let customCategories: Int
    let systemCategories: Int
    let monthlyActivity: [AdminMonthlyActivity]
}
struct AdminMonthlyActivity: Decodable, Identifiable {
    let month: String
    let signups: Int
    let transactions: Int
    var id: String { month }
}

/// Maps backend Goal.title to the user-facing name. Icon is local presentation only;
/// the current backend Goal entity does not expose an icon field.
struct FinanceGoal: Decodable, Identifiable {
    var id: Int
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var deadline: String
    var status: String
    var description: String?
    var userId: Int?
    var icon: String? = nil

    enum CodingKeys: String, CodingKey { case id, title, targetAmount, currentAmount, deadline, status, description, userId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .title) ?? "Meta financiera"
        targetAmount = try c.decodeIfPresent(Double.self, forKey: .targetAmount) ?? 0
        currentAmount = try c.decodeIfPresent(Double.self, forKey: .currentAmount) ?? 0
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        description = try c.decodeIfPresent(String.self, forKey: .description)
        userId = try c.decodeIfPresent(Int.self, forKey: .userId)
        icon = nil
    }
    var progress: Double { targetAmount > 0 ? min(max(currentAmount / targetAmount, 0), 1) : 0 }
}
struct GoalRequest: Encodable {
    let title: String
    let targetAmount: Double
    let currentAmount: Double?
    let deadline: String
    let description: String?
    let status: String? = nil
}
struct AmountRequest: Encodable { let amount: Double; var note: String? = nil }

/// Mirrors PlannedExpense from the backend. IDs are server-issued integers (Long in Java).
struct PlannedExpense: Decodable, Identifiable {
    var id: Int
    var userId: Int?
    var title: String
    var amount: Double
    var categoryId: Int?
    var dueDate: String?
    var notes: String?
    var status: String
    var executedTransactionId: Int?
    var remindAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey { case id, userId, title, amount, categoryId, dueDate, notes, status, executedTransactionId, remindAt, createdAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        userId = try c.decodeIfPresent(Int.self, forKey: .userId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Gasto planificado"
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        categoryId = try c.decodeIfPresent(Int.self, forKey: .categoryId)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        executedTransactionId = try c.decodeIfPresent(Int.self, forKey: .executedTransactionId)
        remindAt = try c.decodeIfPresent(String.self, forKey: .remindAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
    var parsedDueDate: Date? { DateFormatters.parse(dueDate) }
}
struct PlannedExpenseRequest: Encodable {
    let title: String
    let amount: Double
    let categoryId: Int?
    let dueDate: String?
    let notes: String?
    let remindAt: String?
}


struct FinancialAccount: Decodable, Identifiable {
    let id: Int
    let name: String
    let type: String
    let currency: String
    let openingBalance: Double
    let balance: Double
    let archived: Bool
}
struct CreateFinancialAccount: Encodable {
    let name: String
    let type: String
    let currency: String = "COP"
    let openingBalance: Double
}
struct UpdateFinancialAccount: Encodable {
    let name: String
    let type: String
}
struct ArchiveFinancialAccount: Encodable { let archived: Bool }
struct TransferFunds: Encodable {
    let fromAccountId: Int
    let toAccountId: Int
    let amount: Double
    let date: String
    let note: String?
}
struct FinancialTransfer: Decodable, Identifiable {
    let id: Int
    let fromAccountId: Int
    let toAccountId: Int
    let amount: Double
    let date: String
    let note: String?
}

struct RecurringRule: Decodable, Identifiable {
    let id: Int
    let title: String
    let amount: Double
    let type: String
    let categoryId: Int
    let accountId: Int?
    let dayOfMonth: Int
    let nextDueDate: String
    let active: Bool
}
struct CreateRecurringRule: Encodable {
    let title: String
    let amount: Double
    let type: String
    let categoryId: Int
    let accountId: Int?
    let dayOfMonth: Int
}
struct RecurringActivation: Encodable { let active: Bool }
struct ProcessRecurringResult: Decodable { let created: Int }

struct GoalContribution: Decodable, Identifiable {
    let id: Int
    let goalId: Int
    let amount: Double
    let note: String?
    let createdAt: String?
}
struct GoalStatusChange: Encodable { let status: String }

struct PasswordChangeRequest: Encodable {
    let currentPassword: String
    let newPassword: String
    let confirmPassword: String
}
struct PasswordConfirmation: Encodable { let password: String }
struct SecurityActionResponse: Decodable {
    let status: String
    let logoutRequired: Bool
}

struct ChatMessage: Identifiable, Codable { var id = UUID(); var content: String; var role: String; var timestamp = Date() }
struct AdvisorRequest: Encodable { let mensaje: String }
struct AdvisorResponse: Decodable { let respuesta: String }
