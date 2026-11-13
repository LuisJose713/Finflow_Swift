import SwiftUI

struct TransactionRow: View {
    let transaction: FinanceTransaction
    var hideAmount = false
    private var dateDescription: String {
        guard let date = DateFormatters.parse(transaction.date ?? transaction.createdAt) else {
            return "Fecha no disponible"
        }
        return DateFormatters.display.string(from: date)
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.type.lowercased() == "income" ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(transaction.type.lowercased() == "income" ? FinFlowTheme.mint : FinFlowTheme.danger)
                .frame(width: 42, height: 42).background((transaction.type.lowercased() == "income" ? FinFlowTheme.mint : FinFlowTheme.danger).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("\(transaction.type.lowercased() == "income" ? "Ingreso" : "Gasto") · \(dateDescription)")
                    .font(.caption).foregroundStyle(FinFlowTheme.secondaryText)
                if let status = transaction.status, status != "completed" {
                    Text(status == "pending" ? "Pendiente" : "Cancelado")
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(hideAmount ? "••••" : CurrencyFormatter.format(transaction.amount))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.description), \(dateDescription), \(hideAmount ? "importe oculto" : (transaction.type.lowercased() == "income" ? "ingreso" : "gasto") + " " + CurrencyFormatter.format(transaction.amount))")
        .privacySensitive()
    }
}
