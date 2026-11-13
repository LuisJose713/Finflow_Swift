import XCTest

@MainActor
final class FinFlowUITests: XCTestCase {
    private func launch(failure: Bool = false, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FINFLOW_UI_TESTING"] = "1"
        if failure { app.launchEnvironment["FINFLOW_UI_FAILURE"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(es)", "-AppleLocale", "es_CO"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["Correo electrónico"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        email.tap(); email.typeText("ios.qa@example.invalid")
        let password = app.secureTextFields["Contraseña"]
        password.tap(); password.typeText("PruebaSegura2026!")
        app.buttons["auth.submit"].tap()
        let understood = app.buttons["Entendido, continuar a FinFlow"]
        if understood.waitForExistence(timeout: 10) { understood.tap() }
        XCTAssertTrue(app.buttons["navigation.openMenu"].waitForExistence(timeout: 15)
                      || app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func open(_ route: String, in app: XCUIApplication) {
        let menu = app.buttons["navigation.openMenu"]
        if menu.exists {
            menu.tap()
            let destination = app.buttons["navigation.destination.\(route)"]
            for _ in 0..<5 where !destination.isHittable { app.swipeUp() }
            XCTAssertTrue(destination.waitForExistence(timeout: 5))
            destination.tap()
        } else {
            // iPad may use the adaptable sidebar. Open the native More tab.
            let more = app.buttons["Menú"].firstMatch
            if more.exists { more.tap() }
            let labels = ["accounts": "Cuentas y billeteras", "budgets": "Presupuestos", "recurring": "Movimientos recurrentes", "categories": "Categorías", "planned": "Gastos planificados", "reports": "Reportes PDF y Excel", "plans": "Planes FinFlow", "advisor": "Asesor financiero IA", "settings": "Ajustes y privacidad"]
            let link = app.buttons[labels[route] ?? route].firstMatch
            for _ in 0..<5 where !link.isHittable { app.swipeUp() }
            link.tap()
        }
    }

    func testLoginAndRegistrationValidation() {
        let app = launch()
        XCTAssertTrue(app.buttons["auth.submit"].waitForExistence(timeout: 15))
        capture(app, "01-login")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["Ingresa un correo válido y una contraseña de al menos 8 caracteres."].waitForExistence(timeout: 5))
        app.buttons["¿No tienes cuenta? Regístrate"].tap()
        XCTAssertTrue(app.secureTextFields["Confirmar contraseña"].exists)
        capture(app, "02-register")
    }

    func testDashboardChartsAndAmounts() {
        let app = launch(); signIn(app)
        XCTAssertTrue(app.staticTexts["dashboard.balance"].waitForExistence(timeout: 10))
        capture(app, "03-dashboard")
        let picker = app.segmentedControls["dashboard.chartStyle"]
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.exists)
        capture(app, "04-line-chart")
        picker.buttons["Circular"].tap()
        let expense = app.buttons["dashboard.slice.expense"]
        for _ in 0..<3 where !expense.isHittable { app.swipeUp() }
        expense.tap()
        XCTAssertTrue(app.staticTexts["dashboard.donutAmount"].exists)
        capture(app, "05-circular-chart")
    }

    func testEveryFinanceDestinationLoads() {
        let app = launch(); signIn(app)
        for route in ["accounts", "budgets", "recurring", "categories", "planned", "reports", "plans", "advisor", "settings"] {
            open(route, in: app)
            capture(app, "screen-\(route)")
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No pudimos interpretar")).firstMatch.exists)
            if app.buttons["Cerrar"].firstMatch.exists { app.buttons["Cerrar"].firstMatch.tap() }
            else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        }
    }

    func testCreateTransaction() {
        let app = launch(); signIn(app)
        app.buttons["dashboard.addExpense"].tap()
        let title = app.textFields["Título"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap(); title.typeText("Prueba de movimiento iOS")
        let amount = app.textFields["Monto en COP"]
        amount.tap(); amount.typeText("25000")
        if app.buttons["Listo"].exists { app.buttons["Listo"].tap() }
        capture(app, "form-transaction")
        app.buttons["Guardar movimiento"].tap()
        XCTAssertTrue(app.buttons["dashboard.addExpense"].waitForExistence(timeout: 8))
    }

    func testServiceFailureDoesNotInventBalance() {
        let app = launch(failure: true); signIn(app)
        XCTAssertTrue(app.otherElements["dashboard.error"].waitForExistence(timeout: 10)
                      || app.buttons["Reintentar conexión"].exists)
        XCTAssertFalse(app.staticTexts["dashboard.balance"].exists)
        capture(app, "06-service-error")
    }

    func testAccessibilityLargeText() {
        let app = launch(largeText: true)
        XCTAssertTrue(app.buttons["auth.submit"].waitForExistence(timeout: 15))
        capture(app, "07-large-text-login")
    }
}
