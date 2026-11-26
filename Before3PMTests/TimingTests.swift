import Foundation
import XCTest

final class TimingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_532_480)
    private let desk = TaskPreset.builtIns[1]
    private let reading = TaskPreset.builtIns[2]

    private func plan(gap: TimeInterval = 27 * 60, prep: Int = 10, travel: Int = 15) -> TimePlan {
        TimePlan(appointment: Appointment(at: now.addingTimeInterval(gap + Double(prep + travel) * 60),
                                          prep: prep, travel: travel))
    }

    func testExampleAndExactPhaseBoundaries() {
        let day = plan()
        XCTAssertEqual(day.gap(at: now), 27 * 60)
        XCTAssertEqual(day.prepareAt, now.addingTimeInterval(27 * 60))
        XCTAssertEqual(day.leaveAt, now.addingTimeInterval(37 * 60))
        XCTAssertEqual(day.appointment.at, now.addingTimeInterval(52 * 60))
        XCTAssertEqual(day.phase(at: day.prepareAt.addingTimeInterval(-1)), .gap)
        XCTAssertEqual(day.phase(at: day.prepareAt), .prepare)
        XCTAssertEqual(day.phase(at: day.leaveAt), .leave)
        XCTAssertEqual(day.phase(at: day.appointment.at), .appointment)
        XCTAssertEqual(day.gap(at: day.prepareAt), 0)
        XCTAssertEqual(day.gap(at: day.prepareAt.addingTimeInterval(1)), 0)
    }

    func testExactFitOneSecondShortAndZero() {
        XCTAssertEqual(Timing.fit(desk, gap: 600), .full)
        XCTAssertNotNil(Timing.start(desk, confirmedMinutes: 10, plan: plan(gap: 600), at: now))
        XCTAssertEqual(Timing.fit(desk, gap: 599), .shorter(9))
        XCTAssertNil(Timing.start(desk, confirmedMinutes: 10, plan: plan(gap: 599), at: now))
        XCTAssertEqual(Timing.fit(desk, gap: 59), .skip)
        XCTAssertEqual(Timing.fit(desk, gap: 0), .skip)
        XCTAssertNil(Timing.start(desk, confirmedMinutes: 0, plan: plan(gap: 0), at: now))
        XCTAssertEqual(Timing.fit(TaskPreset(name: "Call", minutes: 30, canShorten: false), gap: 599), .skip)
    }

    func testShorterRunRequiresNewConfirmationAtBoundary() throws {
        let day = plan()
        XCTAssertEqual(Timing.fit(reading, gap: day.gap(at: now)), .shorter(20))
        let run = try XCTUnwrap(Timing.start(reading, confirmedMinutes: 20, plan: day, at: now))
        XCTAssertEqual(run.endsAt, now.addingTimeInterval(20 * 60))
        XCTAssertNil(Timing.start(reading, confirmedMinutes: 20, plan: plan(gap: 1199), at: now))
        XCTAssertEqual(Timing.fit(reading, gap: 1199), .shorter(10))
    }

    func testRescheduleCutsTimerWithoutMovingOriginalEndLater() throws {
        var state = LocalState()
        let original = plan()
        state.setAppointment(original.appointment, at: now)
        let run = try XCTUnwrap(Timing.start(desk, confirmedMinutes: 10, plan: plan(), at: now))
        state.run = run
        let earlier = plan(gap: 300)
        state.setAppointment(earlier.appointment, at: now)
        XCTAssertEqual(state.appointment?.id, original.appointment.id)
        XCTAssertEqual(state.appointment?.revision, 1)
        XCTAssertEqual(state.run?.id, run.id)
        XCTAssertEqual(state.run?.endsAt, earlier.prepareAt)
        state.setAppointment(plan(gap: 3600).appointment, at: now)
        XCTAssertEqual(state.run?.endsAt, earlier.prepareAt)
        state.setAppointment(plan(gap: -1).appointment, at: now)
        XCTAssertNil(state.run)
        XCTAssertEqual(state.history.first?.outcome, .interrupted)
    }

    func testFinishAndArchiveAreIdempotentAfterClockRollback() throws {
        var state = LocalState()
        let day = plan(gap: 600)
        state.setAppointment(day.appointment, at: now)
        state.run = try XCTUnwrap(Timing.start(desk, confirmedMinutes: 10, plan: day, at: now))
        state.advance(at: day.appointment.at)
        state.advance(at: now)
        state.finish(.done, at: now)
        XCTAssertNil(state.run)
        XCTAssertNil(state.appointment)
        XCTAssertEqual(state.lastAppointment?.id, day.appointment.id)
        XCTAssertEqual(state.history.map(\.outcome), [.elapsed])
        XCTAssertEqual(state.completedDays, 0)
    }

    func testRemindersMergeAtIdenticalTimesAndExcludePast() throws {
        let day = plan(gap: 600)
        let run = try XCTUnwrap(Timing.start(desk, confirmedMinutes: 10, plan: day, at: now))
        XCTAssertEqual(day.reminders(run: run, after: now).map(\.phase), [.prepare, .leave])
        XCTAssertEqual(day.reminders(run: run, after: day.prepareAt).map(\.phase), [.leave])
        XCTAssertEqual(plan(prep: 0).reminders(run: nil, after: now).map(\.phase), [.leave])
        let online = plan(prep: 0, travel: 0)
        XCTAssertEqual(online.reminders(run: nil, after: now).map(\.phase), [.join])
        XCTAssertEqual(online.phase(at: online.appointment.at), .join)
        XCTAssertEqual(plan(gap: 0).gap(at: now), 0)
        let distinct = plan(gap: 601)
        XCTAssertEqual(distinct.reminders(run: run, after: now).map(\.phase), [.task, .prepare, .leave])
    }

    func testEditingChangesNotificationRevisionAndCancelEndsRun() throws {
        var state = LocalState()
        let original = plan()
        state.setAppointment(original.appointment, at: now)
        state.run = try XCTUnwrap(Timing.start(desk, confirmedMinutes: 10, plan: original, at: now))
        let initialIDs = Set(original.reminders(run: state.run, after: now).map(\.id))
        state.setAppointment(plan(gap: 1200).appointment, at: now)
        let revised = TimePlan(appointment: try XCTUnwrap(state.appointment))
        let revisedIDs = revised.reminders(run: state.run, after: now).map(\.id)
        XCTAssertTrue(initialIDs.isDisjoint(with: revisedIDs))
        XCTAssertTrue(revisedIDs.allSatisfy { $0.hasPrefix("before3pm." + original.appointment.id.uuidString + ".1.") })
        state.cancel(at: now)
        state.cancel(at: now)
        XCTAssertNil(state.appointment)
        XCTAssertNil(state.run)
        XCTAssertEqual(state.history.map(\.outcome), [.interrupted])
    }

    func testCrossMidnightSpringForwardAndRepeatedFallHour() throws {
        let format = ISO8601DateFormatter()
        func date(_ text: String) throws -> Date { try XCTUnwrap(format.date(from: text)) }

        let night = try date("2026-06-16T00:15:00+09:00")
        let prior = try date("2026-06-15T23:40:00+09:00")
        XCTAssertEqual(TimePlan(appointment: Appointment(at: night, prep: 10, travel: 15)).gap(at: prior), 600)

        let beforeSpring = try date("2026-03-08T01:55:00-08:00")
        let afterSpring = try date("2026-03-08T03:15:00-07:00")
        XCTAssertEqual(TimePlan(appointment: Appointment(at: afterSpring, prep: 5, travel: 5)).gap(at: beforeSpring), 600)

        let first = try date("2026-11-01T01:30:00-07:00")
        let second = try date("2026-11-01T01:30:00-08:00")
        XCTAssertEqual(second.timeIntervalSince(first), 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(Timing.alternateWallTime(for: first, calendar: calendar), second)
        XCTAssertEqual(Timing.alternateWallTime(for: second, calendar: calendar), first)
        XCTAssertNil(Timing.alternateWallTime(for: afterSpring, calendar: calendar))
        let appointment = Appointment(at: second, prep: 10, travel: 15, timeZoneID: "America/Los_Angeles")
        XCTAssertEqual(TimePlan(appointment: appointment).gap(at: first), 35 * 60)
        XCTAssertEqual(try JSONDecoder().decode(Appointment.self, from: JSONEncoder().encode(appointment)), appointment)
    }

    func testDepartureCountdownUsesDepartureAndTaskDeadlines() throws {
        let day = plan()
        let run = try XCTUnwrap(Timing.start(desk, confirmedMinutes: 10, plan: day, at: now))
        let initial = try XCTUnwrap(day.departureCountdown(run: run, startedAt: now, at: now))
        XCTAssertEqual(initial.timerInterval, now...day.leaveAt)
        XCTAssertEqual(initial.leaveAt.timeIntervalSince(now), 37 * 60)
        XCTAssertFalse(initial.isOnline)
        XCTAssertEqual(initial.task?.title, desk.title)
        XCTAssertEqual(initial.task?.timerInterval, now...run.endsAt)
        XCTAssertEqual(day.departureCountdown(run: run, startedAt: now, at: run.endsAt.addingTimeInterval(-1)), initial)

        let afterTask = try XCTUnwrap(day.departureCountdown(run: run, startedAt: now, at: run.endsAt))
        XCTAssertNil(afterTask.task)
        XCTAssertEqual(afterTask.timerInterval, initial.timerInterval)
        XCTAssertNotNil(day.departureCountdown(run: nil, startedAt: now, at: day.leaveAt.addingTimeInterval(-1)))
        XCTAssertNil(day.departureCountdown(run: nil, startedAt: now, at: day.leaveAt))
        XCTAssertNil(day.departureCountdown(run: nil, startedAt: now, at: day.leaveAt.addingTimeInterval(1)))
    }

    func testDepartureCountdownUpdatesAfterReschedulingForOnlineAppointment() throws {
        var state = LocalState()
        let original = plan()
        state.setAppointment(original.appointment, at: now)
        state.run = try XCTUnwrap(Timing.start(desk, confirmedMinutes: 10, plan: original, at: now))

        let earlier = plan(gap: 180, prep: 2, travel: 0)
        let editTime = now.addingTimeInterval(60)
        state.setAppointment(earlier.appointment, at: editTime)
        let revised = TimePlan(appointment: try XCTUnwrap(state.appointment))
        let countdown = try XCTUnwrap(revised.departureCountdown(run: state.run, startedAt: now, at: editTime))
        XCTAssertTrue(countdown.isOnline)
        XCTAssertEqual(countdown.leaveAt, earlier.appointment.at)
        XCTAssertEqual(countdown.task?.timerInterval, now...earlier.prepareAt)

        state.cancel(at: editTime)
        XCTAssertNil(state.appointment)
        XCTAssertNil(state.run)
    }

    func testInvalidAppointmentInputs() {
        XCTAssertFalse(plan(gap: 0, prep: 0, travel: 0).isValid(at: now))
        XCTAssertFalse(plan(prep: -1).isValid(at: now))
        XCTAssertFalse(plan(travel: 241).isValid(at: now))
        XCTAssertTrue(plan(prep: 240, travel: 240).isValid(at: now))
    }
}
