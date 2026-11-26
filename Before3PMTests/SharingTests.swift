import CoreGraphics
import CoreImage
import Foundation
import XCTest

final class SharingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_532_480)

    func testPresetRoundTripAndStrictValidation() throws {
        let code = PresetCode(prepMin: 0, travelMin: 240, taskID: "desk")
        let output = try code.encode()
        XCTAssertTrue(output.hasPrefix("BG1:"))
        XCTAssertFalse(output.dropFirst(4).contains("="))
        XCTAssertEqual(try PresetCode.decode(output), code)
        XCTAssertEqual(try PresetCode.decode(output + "\n"), code)
        XCTAssertThrowsError(try PresetCode.decode(output + String(repeating: " ", count: 512)))
        XCTAssertThrowsError(try PresetCode.decode("BG1:0"))
        XCTAssertThrowsError(try PresetCode.decode("BG2:1234"))
        XCTAssertThrowsError(try PresetCode(prepMin: -1, travelMin: 0).encode())
        XCTAssertThrowsError(try PresetCode(prepMin: 0, travelMin: 241).encode())
        XCTAssertThrowsError(try PresetCode(prepMin: 0, travelMin: 0, taskID: "private").encode())
        for json in [
            #"{"v":2,"prepMin":10,"travelMin":15}"#,
            #"{"v":1,"prepMin":10,"travelMin":15,"title":"private"}"#,
            #"{"v":1,"prepMin":1.5,"travelMin":15}"#
        ] {
            let base = Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            XCTAssertThrowsError(try PresetCode.decode("BG1:" + base))
        }
    }

    func testImportOnlyChangesDefaultsAndOldStateDecodes() throws {
        let old = Data(#"{"history":[],"settings":{"defaultPrep":5}}"#.utf8)
        var state = try JSONDecoder().decode(LocalState.self, from: old)
        XCTAssertEqual(state.settings.defaultPrep, 5)
        XCTAssertEqual(state.settings.defaultTravel, 15)
        let appointment = Appointment(at: now.addingTimeInterval(3600), prep: 10, travel: 15)
        state.setAppointment(appointment, at: now)
        state.apply(PresetCode(prepMin: 20, travelMin: 25, taskID: "read"))
        XCTAssertEqual(state.appointment, appointment)
        XCTAssertNil(state.run)
        XCTAssertEqual(state.settings.defaultPrep, 20)
        XCTAssertEqual(state.settings.defaultTravel, 25)
        XCTAssertEqual(state.visibleTasks(hasPro: false).first?.id, "read")
        XCTAssertEqual(try JSONDecoder().decode(LocalState.self, from: JSONEncoder().encode(state)), state)
    }

    func testBasicTaskLimitPreservesExistingDataAndAllowsExplicitSelection() {
        var state = LocalState()
        state.tasks = (1...4).map { TaskPreset(name: "Task \($0)", minutes: 5) }
        XCTAssertEqual(state.visibleTasks(hasPro: true).count, 7)
        XCTAssertEqual(state.visibleTasks(hasPro: false).count, 6)
        state.settings.pickedTaskIDs = [state.tasks[3].id]
        XCTAssertTrue(state.visibleTasks(hasPro: false).contains(state.tasks[3]))
        XCTAssertEqual(state.tasks.count, 4)
    }

    func testMilestoneAndRatingGate() {
        var state = LocalState()
        for day in [0, 0, 1, 2] {
            let start = now.addingTimeInterval(-Double(day) * 86400)
            state.setAppointment(Appointment(at: start.addingTimeInterval(3600), prep: 10, travel: 15), at: start)
            state.run = TaskRun(preset: TaskPreset.builtIns[1], startedAt: start, endsAt: start.addingTimeInterval(600))
            state.finish(.done, at: start.addingTimeInterval(30))
        }
        XCTAssertEqual(state.completedDays, 3)
        XCTAssertFalse(state.sharedOrExported)
        XCTAssertFalse(state.canRequestReview(at: now, hasRoom: false))
        XCTAssertTrue(state.canRequestReview(at: now, hasRoom: true))
        state.lastReviewRequest = now
        XCTAssertFalse(state.canRequestReview(at: now.addingTimeInterval(120 * 86400 - 1), hasRoom: true))
        XCTAssertTrue(state.canRequestReview(at: now.addingTimeInterval(120 * 86400), hasRoom: true))
    }

    func testCSVQuotesCellsAndPreventsFormulaEvaluation() {
        let task = TaskPreset(name: #"  =HYPERLINK("example")"#, minutes: 10)
        let run = TaskRun(preset: task, startedAt: now, endsAt: now.addingTimeInterval(600))
        let csv = HistoryCSV.make([CompletionRecord(run: run, endedAt: run.endsAt, outcome: .done, useDay: "2026-06-15")])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains(#""'  =HYPERLINK(""example"")""#))
        XCTAssertTrue(csv.contains("\r\n"))
        XCTAssertNotEqual(L.t("app.name"), "app.name")
    }

    func testQRFromFullAndDownsampledShareCard() throws {
        let url = ShareCard.downloadURL(appStoreID: "1234567890")
        XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id1234567890")
        XCTAssertEqual(ShareCard.downloadURL(appStoreID: ""), ShareCard.placeholderURL)
        let card = try XCTUnwrap(ShareCard.render(days: 3, url: url))
        let pixels = try XCTUnwrap(card.cgImage)
        XCTAssertEqual(pixels.width, 1080)
        XCTAssertEqual(pixels.height, 1350)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(),
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let full = CIImage(cgImage: pixels)
        let half = full.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        for image in [full, half] {
            let codes = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertTrue(codes.contains(url.absoluteString))
        }
    }
}
