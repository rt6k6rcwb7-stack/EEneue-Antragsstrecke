import XCTest

/// Klickt sich mit gekennzeichneten Beispieldaten durch die App und speichert Screenshots.
/// Zielordner: Umgebungsvariable SCREENSHOT_DIR (über TEST_RUNNER_SCREENSHOT_DIR an xcodebuild).
final class DemoScreenshotTests: XCTestCase {
    var app: XCUIApplication!
    var counter = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func shot(_ name: String) {
        counter += 1
        sleep(1)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let file = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", counter, name))
            try? png.write(to: file)
        }
    }

    func tab(_ label: String) {
        let b = app.tabBars.buttons[label]
        XCTAssertTrue(b.waitForExistence(timeout: 10), "Tab \(label) fehlt")
        b.tap()
    }

    func tapWhenVisible(_ element: XCUIElement, scrollIn container: XCUIElement? = nil, attempts: Int = 6) {
        var i = 0
        while !(element.exists && element.isHittable) && i < attempts {
            (container ?? app).swipeUp()
            i += 1
        }
        if element.exists { element.tap() } else { XCTFail("Element nicht gefunden: \(element)") }
    }

    /// Ersteinrichtung eines neuen Familienmitglieds (Daten werden vorher gelöscht).
    func testOnboarding() {
        app.launchArguments = ["-freshStart"]
        app.launch()
        let next = app.buttons["Weiter"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        shot("onboarding-1-willkommen")
        next.tap()
        let name = app.textFields["Vorname (für die Begrüßung)"]
        if name.waitForExistence(timeout: 5) { name.tap(); name.typeText("Anna") }
        shot("onboarding-2-ueber-dich")
        next.tap(); shot("onboarding-3-ausruestung")
        next.tap(); shot("onboarding-4-rhythmus")
        next.tap(); shot("onboarding-5-gesundheit")
        next.tap()
        let health = app.switches["Apple Health lesen (Ruhepuls, HRV, Schlaf, Aktivität)"]
        if health.waitForExistence(timeout: 5), (health.value as? String) == "1" { health.tap() }
        shot("onboarding-6-datenschutz")
        app.buttons["Plan erstellen und loslegen"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        shot("onboarding-7-fertig")
    }

    func testDemoTour() {
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        shot("dashboard")
        app.swipeUp(); shot("dashboard-regeneration")
        app.swipeDown(); app.swipeDown()

        tab("Plan"); shot("plan")
        let firstWorkout = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Kraft'")).firstMatch
        if firstWorkout.waitForExistence(timeout: 5) { firstWorkout.tap(); shot("plan-einheit"); app.navigationBars.buttons.firstMatch.tap() }

        tab("Übungen"); shot("bibliothek")
        let goblet = app.staticTexts["Kettlebell Goblet Squat"]
        if goblet.waitForExistence(timeout: 5) { goblet.tap(); sleep(1); shot("uebung-detail"); app.swipeUp(); shot("uebung-technik"); app.navigationBars.buttons.firstMatch.tap() }

        tab("Fortschritt"); shot("fortschritt-training")
        app.swipeUp(); shot("fortschritt-kraft")
        app.swipeDown(); app.swipeDown()
        let vitals = app.buttons["Vitaldaten"]
        if vitals.waitForExistence(timeout: 5) { vitals.tap(); shot("fortschritt-vitaldaten") }

        tab("Training"); shot("training-check-in")
        tapWhenVisible(app.buttons["Empfehlung berechnen"])
        sleep(1); shot("training-empfehlung")
        let start = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Training starten' OR label BEGINSWITH 'Angepasst starten' OR label BEGINSWITH 'Regenerationseinheit'")).firstMatch
        tapWhenVisible(start)
        XCTAssertTrue(app.buttons["Satz erledigt"].waitForExistence(timeout: 10))
        shot("player-uebung")
        for _ in 0..<5 { app.buttons["Satz erledigt"].tap() }   // Aufwärmen
        sleep(2); shot("player-hauptuebung")
        app.buttons["Satz erledigt"].tap()
        sleep(2); shot("player-pause")
        app.buttons["Beenden"].tap()
        let confirm = app.buttons["Beenden und speichern"]
        if confirm.waitForExistence(timeout: 5) { confirm.tap(); sleep(1); shot("feedback") }
        let save = app.buttons["Speichern"]
        if save.waitForExistence(timeout: 5) { save.tap() }

        let gear = app.buttons["Einstellungen"].firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap(); shot("einstellungen")
            let devices = app.buttons["Geräteverbindungen"]
            if devices.waitForExistence(timeout: 5) { devices.tap(); shot("geraete") }
        }
    }
}
