import SwiftUI
import Charts

struct FinancialSummaryCharts: View {
    let stats: TransactionStats
    @AppStorage("finflow.dashboard.chartStyle") private var style = "line"
    @State private var selectedMonth: String?
    @State private var selectedAngle: Double?
    @State private var selectedType = "income"

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let amount: Double
        let color: Color
    }
    private var slices: [Slice] {
        [Slice(id: "income", label: "Ingresos", amount: stats.totalIncome, color: FinFlowTheme.mint),
         Slice(id: "expense", label: "Gastos", amount: stats.totalExpenses, color: FinFlowTheme.danger)]
    }
    private var currentMonth: MonthlyData? {
        stats.monthlyData.first { $0.month == selectedMonth } ?? stats.monthlyData.last
    }
    private var currentSlice: Slice {
        if let angle = selectedAngle {
            return angle <= stats.totalIncome ? slices[0] : slices[1]
        }
        return slices.first { $0.id == selectedType } ?? slices[0]
    }

    var body: some View {
        SectionCard(title: "Tu panorama financiero", subtitle: style == "circle" ? "Todo tu historial · COP" : "Evolución mensual · COP") {
            Picker("Tipo de gráfico", selection: $style) {
                Text("Lineal").tag("line")
                Text("Circular").tag("circle")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("dashboard.chartStyle")
            if style == "circle" { circularChart } else { lineChart }
        }
        if !stats.categoryData.isEmpty {
            SectionCard(title: "Gastos por categoría", subtitle: "Las seis categorías con más gastos · COP") {
                ForEach(Array(stats.categoryData.sorted { $0.amount > $1.amount }.prefix(6))) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(category.category).font(.subheadline)
                            Spacer(minLength: 12)
                            Text(CurrencyFormatter.format(category.amount)).font(.subheadline.weight(.semibold))
                                .monospacedDigit().fixedSize()
                        }
                        ProgressView(value: min(1, max(0, category.percentage / 100)))
                            .tint(FinFlowTheme.accent)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private var lineChart: some View {
        if let month = currentMonth {
            Text(monthLabel(month.month)).font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("dashboard.selectedMonth")
            amounts(income: month.income, expenses: month.expenses)
            Chart {
                ForEach(stats.monthlyData) { point in
                    LineMark(x: .value("Mes", point.month), y: .value("Ingresos", point.income), series: .value("Serie", "Ingresos"))
                        .foregroundStyle(FinFlowTheme.mint).symbol(Circle())
                    LineMark(x: .value("Mes", point.month), y: .value("Gastos", point.expenses), series: .value("Serie", "Gastos"))
                        .foregroundStyle(FinFlowTheme.danger).symbol(.square)
                }
                RuleMark(x: .value("Mes", month.month))
                    .foregroundStyle(FinFlowTheme.secondaryText.opacity(0.4))
            }
            .chartXSelection(value: $selectedMonth)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(String.self) { Text(shortMonthLabel(raw)) }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 190)
            .accessibilityLabel("Evolución mensual de ingresos y gastos")
            Text("Toca o desliza sobre el gráfico para consultar un mes.")
                .font(.caption).foregroundStyle(.secondary)
            // An equivalent control also makes every month available to VoiceOver.
            Picker("Consultar mes", selection: Binding(get: { month.month }, set: { selectedMonth = $0 })) {
                ForEach(stats.monthlyData) { item in Text(monthLabel(item.month)).tag(item.month) }
            }
            .accessibilityIdentifier("dashboard.monthPicker")
        } else {
            EmptyState(icon: "chart.xyaxis.line", title: "Tu historia empieza aquí",
                       message: "Al registrar movimientos realizados verás su evolución mensual.")
        }
    }

    @ViewBuilder private var circularChart: some View {
        if stats.totalIncome + stats.totalExpenses > 0 {
            Chart(slices.filter { $0.amount > 0 }) { slice in
                SectorMark(angle: .value("Importe", slice.amount), innerRadius: .ratio(0.72), angularInset: 2)
                    .foregroundStyle(slice.color)
                    .opacity(currentSlice.id == slice.id ? 1 : 0.42)
                    .cornerRadius(5)
            }
            .chartAngleSelection(value: $selectedAngle)
            .chartLegend(.hidden)
            .frame(height: 215)
            .overlay {
                VStack(spacing: 6) {
                    Text(currentSlice.label).font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(currentSlice.amount))
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle(currentSlice.color)
                        .accessibilityIdentifier("dashboard.donutAmount")
                }.frame(maxWidth: 175).allowsHitTesting(false)
            }
            .accessibilityLabel("Distribución entre ingresos y gastos de todo el historial")
            ForEach(slices) { slice in
                Button {
                    selectedType = slice.id; selectedAngle = nil
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label)
                        Spacer(minLength: 8)
                        Text(CurrencyFormatter.format(slice.amount)).fontWeight(.semibold).monospacedDigit()
                        Image(systemName: currentSlice.id == slice.id ? "checkmark.circle.fill" : "circle")
                    }
                    .font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.slice.\(slice.id)")
                .accessibilityAddTraits(currentSlice.id == slice.id ? .isSelected : [])
            }
            Text("Los importes incluyen únicamente movimientos realizados en COP.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            EmptyState(icon: "chart.pie", title: "Aún no hay importes", message: "Registra un ingreso o gasto realizado para ver su distribución.")
        }
    }

    private func amounts(income: Double, expenses: Double) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { amount("Ingresos", value: income, color: FinFlowTheme.mint); amount("Gastos", value: expenses, color: FinFlowTheme.danger) }
            VStack(alignment: .leading, spacing: 10) { amount("Ingresos", value: income, color: FinFlowTheme.mint); amount("Gastos", value: expenses, color: FinFlowTheme.danger) }
        }
    }

    private func amount(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(CurrencyFormatter.format(value)).font(.subheadline.weight(.semibold))
                .monospacedDigit().foregroundStyle(color)
        }.accessibilityElement(children: .combine)
    }
    private func monthLabel(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else { return raw }
        return "\(Calendar.current.monthSymbols[month - 1].capitalized) \(parts[0])"
    }
    private func shortMonthLabel(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2 else { return raw }
        return "\(parts[1])/\(parts[0].suffix(2))"
    }
}
