import Foundation
import XCTest

final class FlowUITests: XCTestCase {
    private enum Language: String, CaseIterable {
        case english = "en"
        case simplified = "zh-Hans"
        case traditional = "zh-Hant"

        var locale: String {
            switch self {
            case .english: return "en_US"
            case .simplified: return "zh_CN"
            case .traditional: return "zh_TW"
            }
        }

        var gapTitle: String {
            switch self {
            case .english: return "Free time"
            case .simplified: return "可用空档"
            case .traditional: return "可用空檔"
            }
        }
    }

    private var app: XCUIApplication!
    private var tapCount = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ fixture: String, language: Language = .english, reset: Bool = true,
                        extra: [String] = [], environment: [String: String] = [:]) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-fixture", fixture,
                               "-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale]
            + (reset ? ["-reset"] : []) + extra
        app.launchEnvironment = environment
        app.launch()
        tapCount = 0
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.buttons.matching(identifier: id)
        _ = matches.firstMatch.waitForExistence(timeout: 6)
        for pass in 0..<8 {
            if let target = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                tap(target)
                return
            }
            if pass < 4 { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("Button not hittable: \(id)", file: file, line: line)
    }

    private func tap(_ element: XCUIElement) {
        element.tap()
        tapCount += 1
    }

    private func waitForText(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[id].firstMatch.waitForExistence(timeout: 8), id, file: file, line: line)
    }

    private func replace(_ id: String, with text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        let count = (field.value as? String)?.count ?? 0
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2))
        field.typeText(text)
    }

    private func shot(_ name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let env = ProcessInfo.processInfo.environment
        if let path = env["SHOTS_DIR"] ?? env["TEST_RUNNER_SHOTS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }

    func testFirstAppointmentAndRelaunchRestore() {
        launch("empty")
        XCTAssertTrue(app.buttons["appointment.date"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["appointment.prep"].value as? String, "10")
        XCTAssertEqual(app.textFields["appointment.travel"].value as? String, "15")
        tap("appointment.save")
        waitForText("appointment.validation")
        tap("appointment.date")
        tap("appointment.save")
        waitForText("phase.gap")
        tap("task.desk")
        waitForText("run.timer")
        let status = app.staticTexts["reminder.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        launch("empty", reset: false)
        waitForText("run.timer")
        tap("run.done")
        waitForText("phase.gap")
        tap("home.settings")
        tap("settings.history")
        XCTAssertTrue(app.staticTexts["Completed"].exists)
    }

    func testStartingTaskShowsInAppCountdown() {
        launch("gap")
        waitForText("phase.gap")
        tap("task.desk")
        waitForText("run.timer")
        XCTAssertEqual(app.staticTexts["run.timer"].label, "10 min")
        XCTAssertTrue(app.buttons["run.done"].exists)
        XCTAssertTrue(app.buttons["run.stop"].exists)
    }

    func testShortVersionAndSkip() {
        launch("gap")
        tap("task.read")
        waitForText("short.title")
        tap("short.skip")
        waitForText("phase.gap")
        XCTAssertFalse(app.staticTexts["run.timer"].exists)
        tap("task.read")
        XCTAssertEqual(app.buttons["short.start"].label, "Start 20 min")
        tap("short.start")
        waitForText("run.timer")
        tap("run.stop")
        waitForText("phase.gap")
    }

    func testEarlierAppointmentCutsRunAndCancelClearsHome() {
        launch("gap")
        tap("task.desk")
        tap("home.edit")
        replace("appointment.prep", with: "50")
        tap("appointment.save")
        waitForText("phase.prepare")
        XCTAssertFalse(app.staticTexts["run.timer"].exists)
        tap("home.edit")
        tap("appointment.cancel")
        XCTAssertTrue(app.buttons["appointment.date"].waitForExistence(timeout: 8))
    }

    func testRescheduleAndCancelEachTakeTwoTaps() {
        launch("gap", language: .simplified)
        waitForText("home.appointmentTime")
        let appointmentTime = app.staticTexts["home.appointmentTime"]
        let originalTime = appointmentTime.label
        XCTAssertEqual(app.buttons["home.edit"].label, "改期")

        tap("home.edit")
        let dateWheel = app.pickerWheels.firstMatch
        XCTAssertTrue(dateWheel.waitForExistence(timeout: 8))
        XCTAssertTrue(dateWheel.isHittable)
        dateWheel.swipeUp()
        XCTAssertEqual(app.buttons["appointment.save"].firstMatch.label, "保存")
        tap("appointment.save")
        let rescheduled = NSPredicate(format: "exists == true AND label != %@", originalTime)
        expectation(for: rescheduled, evaluatedWith: appointmentTime)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(tapCount, 2)

        tapCount = 0
        tap("home.edit")
        tap("appointment.cancel")
        XCTAssertTrue(app.buttons["appointment.date"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["home.edit"].exists)
        XCTAssertEqual(tapCount, 2)
    }

    func testReminderStatesAndArrival() {
        launch("gap")
        tap("reminder.enable")
        let reminder = app.staticTexts["reminder.status"]
        let on = NSPredicate(format: "exists == true AND label == %@", "Local reminders are on")
        expectation(for: on, evaluatedWith: reminder)
        waitForExpectations(timeout: 8)
        launch("denied")
        XCTAssertTrue(app.buttons["reminder.settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["task.desk"].exists)
        launch("ready")
        waitForText("phase.prepare")
        XCTAssertFalse(app.buttons["task.desk"].exists)
        launch("leave")
        waitForText("phase.leave")
        launch("arrived")
        waitForText("phase.arrived")
        XCTAssertTrue(app.buttons["appointment.date"].exists)
        launch("online")
        waitForText("phase.arrived")
        XCTAssertEqual(app.staticTexts["phase.arrived"].label, "Join now")
    }

    func testShareCopyImportAndCSV() {
        let json = #"{"prepMin":20,"travelMin":25,"v":1}"#
        let base = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        launch("milestone", environment: ["UITEST_PRESET_CODE": "BG1:" + base + "\n"])
        tap("home.share")
        tap("share.image")
        waitForText("share.requested")
        tap("share.copy")
        waitForText("share.copied")
        tap("share.close")
        tap("home.settings")
        tap("import.paste")
        waitForText("import.preview")
        tap("import.use")
        waitForText("import.status")
        XCTAssertTrue(app.staticTexts["Preset applied to new appointments."].exists)
        app.swipeDown()
        tap("settings.history")
        tap("history.export")
        waitForText("share.requested")
    }

    func testHomeImportsPresetFileInThreeTaps() throws {
        launch("empty", extra: ["-import-file-fixture", "1"])
        XCTAssertTrue(app.textFields["appointment.prep"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["appointment.prep"].value as? String, "10")
        XCTAssertEqual(app.textFields["appointment.travel"].value as? String, "15")

        tap("home.importPreset")
        waitForText("import.preview")
        XCTAssertEqual(app.staticTexts["import.preview"].label, "20 min to get ready · 25 min to travel")
        tap("import.use")
        XCTAssertEqual(tapCount + 1, 3)

        let prep = app.textFields["appointment.prep"]
        let travel = app.textFields["appointment.travel"]
        expectation(for: NSPredicate(format: "exists == true AND value == %@", "20"), evaluatedWith: prep)
        expectation(for: NSPredicate(format: "exists == true AND value == %@", "25"), evaluatedWith: travel)
        waitForExpectations(timeout: 8)
    }

    func testExpiredKeepsCoreAndExistingHistory() {
        launch("expired", extra: ["-expired"])
        XCTAssertTrue(app.buttons["task.desk"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["task.fixture.3"].exists)
        XCTAssertFalse(app.buttons["task.fixture.4"].exists)
        tap("task.desk")
        waitForText("run.timer")
        tap("run.done")
        tap("home.settings")
        tap("settings.history")
        XCTAssertTrue(app.staticTexts["Completed"].firstMatch.exists)
        tap("history.export")
        waitForText("paywall.state")
        XCTAssertTrue(app.buttons["paywall.trial"].exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
    }

    func testAccessibilitySizeKeepsCoreControlsReachable() {
        launch("gap", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        waitForText("phase.gap")
        tap("task.desk")
        tap("run.done")
        waitForText("phase.gap")
    }

    func testStoreScreenshots() throws {
        for language in Language.allCases {
            let prefix = "store-" + language.rawValue
            launch("gap", language: language)
            waitForText("phase.gap")
            XCTAssertEqual(app.staticTexts["phase.gap"].label, language.gapTitle)
            try shot(prefix + "-01-gap")

            tap("task.desk")
            waitForText("run.timer")
            try shot(prefix + "-02-task")

            tap("run.stop")
            tap("task.read")
            waitForText("short.title")
            try shot(prefix + "-03-short")

            launch("ready", language: language)
            waitForText("phase.prepare")
            try shot(prefix + "-04-prepare")

            launch("milestone", language: language)
            tap("home.share")
            XCTAssertTrue(app.images["share.card"].firstMatch.waitForExistence(timeout: 8))
            try shot(prefix + "-05-milestone")
        }
    }

    func testPaidScreenshot() throws {
        launch("gap", language: .simplified, extra: ["-paywall", "-expired"])
        waitForText("paywall.state")
        let ended = NSPredicate(format: "exists == true AND label == %@", "30 天试用已结束")
        expectation(for: ended, evaluatedWith: app.staticTexts["paywall.state"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["paywall.buy"].exists)
        XCTAssertTrue(app.buttons["paywall.trial"].exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        try shot("paid-01-paywall")
    }
}
