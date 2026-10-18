import Adhan
import Foundation
import XCTest
@testable import PrayerKit

final class PrayerKitTests: XCTestCase {
    private let cairo = SavedLocation(
        latitude: 30.0444, longitude: 31.2357, name: "Cairo", countryCode: "EG",
        timeZoneIdentifier: "Africa/Cairo", source: .manual
    )

    private func settings(_ edit: (inout PrayerSettings) -> Void = { _ in }) -> PrayerSettings {
        var settings = PrayerSettings()
        settings.apply(location: cairo)
        edit(&settings)
        return settings
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testScheduleIsOrderedAndOnTheLocationDay() throws {
        let calculator = try XCTUnwrap(PrayerCalculator(settings: settings()))
        // 23:30 UTC is already the next day in Cairo.
        let schedule = try XCTUnwrap(calculator.schedule(for: date("2026-03-12T23:30:00Z")))
        XCTAssertEqual(schedule.day.day, 13)
        let times = PrayerName.allCases.map(schedule.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(calculator.calendar.component(.day, from: schedule.dhuhr), 13)
    }

    func testAdjustmentsShiftOnlyTheirPrayer() throws {
        let base = try XCTUnwrap(PrayerCalculator(settings: settings())?.schedule(for: date("2026-03-13T10:00:00Z")))
        let adjusted = try XCTUnwrap(PrayerCalculator(settings: settings { $0.adjustments.asr = 7 })?
            .schedule(for: date("2026-03-13T10:00:00Z")))
        XCTAssertEqual(adjusted.asr.timeIntervalSince(base.asr), 7 * 60, accuracy: 60)
        XCTAssertEqual(adjusted.dhuhr, base.dhuhr)
        XCTAssertEqual(adjusted.maghrib, base.maghrib)
    }

    func testHanafiAsrIsLater() throws {
        let now = date("2026-03-13T10:00:00Z")
        let shafi = try XCTUnwrap(PrayerCalculator(settings: settings())?.schedule(for: now))
        let hanafi = try XCTUnwrap(PrayerCalculator(settings: settings { $0.madhab = .hanafi })?.schedule(for: now))
        XCTAssertGreaterThan(hanafi.asr, shafi.asr)
    }

    func testMomentBeforeFajrSpansFromYesterdaysIsha() throws {
        let calculator = try XCTUnwrap(PrayerCalculator(settings: settings()))
        let today = try XCTUnwrap(calculator.schedule(for: date("2026-03-13T10:00:00Z")))
        let yesterday = try XCTUnwrap(calculator.schedule(dayOffset: -1, from: today.dhuhr))
        let moment = try XCTUnwrap(calculator.moment(at: today.fajr.addingTimeInterval(-60)))
        XCTAssertEqual(moment.current, .isha)
        XCTAssertEqual(moment.currentStart, yesterday.isha)
        XCTAssertEqual(moment.next, .fajr)
        XCTAssertEqual(moment.nextTime, today.fajr)
        XCTAssertEqual(moment.segment, .ishaToFajr)
    }

    func testMomentDuringTheDayAndAfterIsha() throws {
        let calculator = try XCTUnwrap(PrayerCalculator(settings: settings()))
        let today = try XCTUnwrap(calculator.schedule(for: date("2026-03-13T10:00:00Z")))
        let tomorrow = try XCTUnwrap(calculator.schedule(dayOffset: 1, from: today.dhuhr))

        let atAsr = try XCTUnwrap(calculator.moment(at: today.asr))
        XCTAssertEqual(atAsr.current, .asr)
        XCTAssertEqual(atAsr.next, .maghrib)
        XCTAssertEqual(atAsr.segment, .asrToMaghrib)
        XCTAssertEqual(atAsr.progress(at: today.asr), 0)

        let late = try XCTUnwrap(calculator.moment(at: today.isha.addingTimeInterval(60)))
        XCTAssertEqual(late.current, .isha)
        XCTAssertEqual(late.next, .fajr)
        XCTAssertEqual(late.nextTime, tomorrow.fajr)
    }

    func testPlanRenamesFridayDhuhrAndSkipsThePast() throws {
        let calculator = try XCTUnwrap(PrayerCalculator(settings: settings()))
        // 2026-03-13 is a Friday.
        let friday = try XCTUnwrap(calculator.schedule(for: date("2026-03-13T10:00:00Z")))
        XCTAssertTrue(calculator.isFriday(friday.dhuhr))
        var notifications = NotificationSettings()
        notifications.reminders = [.dhuhr]
        let now = friday.fajr.addingTimeInterval(60)
        let plan = NotificationPlanner.plan(calculator: calculator, settings: notifications, from: now, days: 2)

        XCTAssertFalse(plan.contains { $0.fireDate <= now })
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { $0.identifier.hasPrefix(PlannedNotification.identifierPrefix) })

        let fridayDhuhr = try XCTUnwrap(plan.first { $0.kind == .atTime && $0.fireDate == friday.dhuhr })
        XCTAssertEqual(fridayDhuhr.title, "Jumu'ah")
        let reminder = try XCTUnwrap(plan.first { $0.kind == .reminder && $0.prayer == .dhuhr })
        XCTAssertEqual(reminder.fireDate, friday.dhuhr.addingTimeInterval(-15 * 60))

        let saturdayDhuhr = try XCTUnwrap(plan.last { $0.kind == .atTime && $0.prayer == .dhuhr })
        XCTAssertEqual(saturdayDhuhr.title, "Dhuhr")
        XCTAssertFalse(plan.contains { $0.prayer == .sunrise })
    }

    func testPlanHonoursDisabledAndDuha() throws {
        let calculator = try XCTUnwrap(PrayerCalculator(settings: settings()))
        let now = date("2026-03-13T00:00:00Z")
        var off = NotificationSettings()
        off.enabled = false
        XCTAssertTrue(NotificationPlanner.plan(calculator: calculator, settings: off, from: now).isEmpty)

        var duha = NotificationSettings()
        duha.atTime = []
        duha.duha = true
        let plan = NotificationPlanner.plan(calculator: calculator, settings: duha, from: now, days: 1)
        let sunrise = try XCTUnwrap(calculator.schedule(for: now)).sunrise
        XCTAssertEqual(plan.map(\.kind), [.duha])
        XCTAssertEqual(plan.first?.fireDate, sunrise.addingTimeInterval(20 * 60))
    }

    func testCountdownRoundsUp() {
        let now = date("2026-03-13T10:00:00Z")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(30)), "1m")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(42 * 60)), "42m")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(3 * 3600 + 5 * 60)), "3h 05m")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(-10)), "0m")
    }

    func testTimeFormatUsesLocationZone() {
        let instant = date("2026-03-13T10:05:00Z")
        let cairoZone = TimeZone(identifier: "Africa/Cairo")!
        XCTAssertEqual(PrayerFormat.time(instant, in: cairoZone, use24Hour: true), "12:05")
        XCTAssertEqual(PrayerFormat.time(instant, in: cairoZone, use24Hour: false), "12:05 PM")
    }

    func testRegionalDefaultsRespectAnExplicitChoice() {
        var settings = PrayerSettings()
        settings.apply(location: cairo)
        XCTAssertEqual(settings.method, .egyptian)
        settings.method = .karachi
        settings.hasChosenMethod = true
        settings.apply(location: cairo)
        XCTAssertEqual(settings.method, .karachi)
        XCTAssertEqual(RegionalDefaults.method(forCountryCode: nil), .muslimWorldLeague)
        XCTAssertEqual(RegionalDefaults.method(forCountryCode: "gb"), .moonsightingCommittee)
    }

    func testSettingsDecodeOlderPayloads() throws {
        let decoded = try JSONDecoder().decode(PrayerSettings.self, from: Data(#"{"madhab":2}"#.utf8))
        XCTAssertEqual(decoded.madhab, .hanafi)
        XCTAssertEqual(decoded.method, .muslimWorldLeague)
        XCTAssertEqual(decoded.notifications, NotificationSettings())

        var original = settings { $0.highLatitudeRule = .seventhOfTheNight; $0.notifications.reminders = [.fajr] }
        original.use24HourClock = true
        let roundTrip = try JSONDecoder().decode(PrayerSettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(roundTrip, original)
    }

    func testCitySearchParsesNominatim() throws {
        let json = #"""
        [{"place_id":123,"lat":"51.5073","lon":"-0.1276","name":"London",
          "display_name":"London, Greater London, England, United Kingdom",
          "address":{"city":"London","country":"United Kingdom","country_code":"gb"}},
         {"lat":"bad","lon":"0","display_name":"Nowhere"}]
        """#
        let results = try CitySearch.parse(Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "London")
        XCTAssertEqual(results[0].countryCode, "GB")
        XCTAssertEqual(results[0].id, "123")
        XCTAssertThrowsError(try CitySearch.parse(Data("{}".utf8)))

        let request = CitySearch(userAgent: "PrayerBar-test").request(for: "Cairo, Egypt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "PrayerBar-test")
        XCTAssertTrue(request.url?.absoluteString.contains("q=Cairo,%20Egypt") ?? false)
    }
}
