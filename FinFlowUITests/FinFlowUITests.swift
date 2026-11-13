import XCTest

@MainActor
final class FinFlowUITests: XCTestCase {
    private func launch(failure: Bool = false, largeText: Bool = false, admin: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FINFLOW_UI_TESTING"] = "1"
        if failure { app.launchEnvironment["FINFLOW_UI_FAILURE"] = "1" }
        if admin { app.launchEnvironment["FINFLOW_UI_ADMIN"] = "1" }
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
        let understood = app.buttons["privacy.continue"]
        XCTAssertTrue(understood.waitForExistence(timeout: 15))
        tap(understood)
        XCTAssertTrue(understood.waitForNonExistence(timeout: 8), "Privacy notice must close before entering FinFlow")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Cerrar menú"].exists, "A closed drawer must not expose its modal controls")
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed,
                       "Control must be visible and interactive: \(element)", file: file, line: line)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Control must be reachable by scrolling: \(element)")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func open(_ route: String, in app: XCUIApplication) {
        let menu = app.buttons["navigation.openMenu"]
        if menu.exists {
            tap(menu)
            let destination = app.buttons["navigation.destination.\(route)"]
            reveal(destination, in: app)
            tap(destination)
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
        let circular = picker.buttons["Circular"]
        reveal(circular, in: app)
        XCTAssertTrue(picker.exists)
        capture(app, "04-line-chart")
        tap(circular)
        let expense = app.buttons["dashboard.slice.expense"]
        reveal(expense, in: app)
        tap(expense)
        XCTAssertTrue(app.staticTexts["dashboard.donutAmount"].exists)
        capture(app, "05-circular-chart")
    }

    func testEveryFinanceDestinationLoads() {
        let app = launch(); signIn(app)
        let loadedContent = ["accounts": "Cuenta principal", "budgets": "Alimentación", "recurring": "Internet del hogar", "categories": "Trabajo", "planned": "Matrícula universitaria", "reports": "Compartir PDF", "plans": "Tu plan actual", "advisor": "Tu asistente financiero", "settings": "Cuenta"]
        for route in ["accounts", "budgets", "recurring", "categories", "planned", "reports", "plans", "advisor", "settings"] {
            open(route, in: app)
            let content = loadedContent[route]!
            XCTAssertTrue(app.staticTexts[content].firstMatch.waitForExistence(timeout: 8)
                          || app.buttons[content].firstMatch.exists, "Missing content in \(route)")
            capture(app, "screen-\(route)")
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No pudimos interpretar")).firstMatch.exists)
            if app.buttons["Cerrar"].firstMatch.exists { app.buttons["Cerrar"].firstMatch.tap() }
            else if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        }
    }

    func testCreateTransaction() {
        let app = launch(); signIn(app)
        let addExpense = app.buttons["dashboard.addExpense"]
        reveal(addExpense, in: app)
        tap(addExpense)
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

    func testCreateGoalAndAdvisorChat() {
        let app = launch(); signIn(app)
        app.tabBars.buttons["Metas"].tap()
        XCTAssertTrue(app.buttons["goals.add"].waitForExistence(timeout: 5))
        app.buttons["goals.add"].tap()
        let name = app.textFields["Nombre de la meta"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Meta de prueba iOS")
        let amount = app.textFields["Monto objetivo (COP)"]
        amount.tap(); amount.typeText("2000000")
        if app.buttons["Listo"].exists { app.buttons["Listo"].tap() }
        capture(app, "form-goal")
        app.buttons["Guardar meta"].tap()
        XCTAssertTrue(app.buttons["goals.add"].waitForExistence(timeout: 8))
        open("advisor", in: app)
        let input = app.textFields["advisor.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Quiero organizar mi presupuesto")
        app.buttons["advisor.send"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Podemos empezar por definir")).firstMatch.waitForExistence(timeout: 8))
        capture(app, "advisor-conversation")
    }

    func testSecurityAndAccountDeletionConfirmation() {
        let app = launch(); signIn(app)
        open("settings", in: app)
        app.buttons["Contraseña y sesiones"].tap()
        XCTAssertTrue(app.switches["security.biometricToggle"].waitForExistence(timeout: 5))
        capture(app, "security")
        let password = app.secureTextFields["security.deletePassword"]
        for _ in 0..<7 where !password.isHittable { app.swipeUp() }
        password.tap(); password.typeText("PruebaSegura2026!")
        let confirmation = app.textFields["security.deleteConfirmation"]
        confirmation.tap(); confirmation.typeText("ELIMINAR")
        if app.buttons["Listo"].exists { app.buttons["Listo"].tap() }
        let remove = app.buttons["Eliminar mi cuenta definitivamente"]
        for _ in 0..<3 where !remove.isHittable { app.swipeUp() }
        remove.tap()
        XCTAssertTrue(app.buttons["Sí, eliminar cuenta"].waitForExistence(timeout: 5))
        capture(app, "account-deletion-confirmation")
        app.buttons["Cancelar"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Eliminar mi cuenta definitivamente"].exists)
    }

    func testDrawerSwipeAwayFromScreenEdge() {
        let app = launch(); signIn(app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.30))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.30))
        start.press(forDuration: 0.05, thenDragTo: finish)
        XCTAssertTrue(app.buttons["Cerrar menú"].waitForExistence(timeout: 5))
        capture(app, "drawer-swipe")
    }

    func testAdministratorDestinationsWithSyntheticRole() {
        let app = launch(admin: true); signIn(app)
        for route in ["admin", "billing"] {
            open(route, in: app)
            capture(app, "screen-\(route)")
            XCTAssertFalse(app.staticTexts["Acceso restringido"].exists)
            app.buttons["Cerrar"].firstMatch.tap()
        }
    }
}
