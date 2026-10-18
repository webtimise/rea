import Adhan
import Foundation

/// The six stretches of the day between consecutive prayer boundaries.
public enum DaySegment: String, CaseIterable {
    case fajrToSunrise, sunriseToDhuhr, dhuhrToAsr, asrToMaghrib, maghribToIsha, ishaToFajr

    public init(startingAt prayer: PrayerName) {
        switch prayer {
        case .fajr: self = .fajrToSunrise
        case .sunrise: self = .sunriseToDhuhr
        case .dhuhr: self = .dhuhrToAsr
        case .asr: self = .asrToMaghrib
        case .maghrib: self = .maghribToIsha
        case .isha: self = .ishaToFajr
        }
    }
}

public struct DaySchedule: Equatable {
    /// Gregorian day in the location's time zone.
    public let day: DateComponents
    public let fajr: Date
    public let sunrise: Date
    public let dhuhr: Date
    public let asr: Date
    public let maghrib: Date
    public let isha: Date

    init(day: DateComponents, times: PrayerTimes) {
        self.day = day
        fajr = times.fajr
        sunrise = times.sunrise
        dhuhr = times.dhuhr
        asr = times.asr
        maghrib = times.maghrib
        isha = times.isha
    }

    public func time(_ prayer: PrayerName) -> Date {
        switch prayer {
        case .fajr: fajr
        case .sunrise: sunrise
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }

    public var entries: [(prayer: PrayerName, time: Date)] {
        PrayerName.allCases.map { ($0, time($0)) }
    }
}

/// Where `now` falls between two prayer boundaries.
public struct PrayerMoment: Equatable {
    public let current: PrayerName
    public let currentStart: Date
    public let next: PrayerName
    public let nextTime: Date

    public var segment: DaySegment { DaySegment(startingAt: current) }

    /// Fraction of the current segment that has elapsed, in 0...1.
    public func progress(at now: Date) -> Double {
        let total = nextTime.timeIntervalSince(currentStart)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(currentStart) / total))
    }
}

public struct PrayerCalculator {
    public let coordinates: Coordinates
    public let timeZone: TimeZone
    public let parameters: CalculationParameters

    public init(coordinates: Coordinates, timeZone: TimeZone, parameters: CalculationParameters) {
        self.coordinates = coordinates
        self.timeZone = timeZone
        self.parameters = parameters
    }

    public init?(settings: PrayerSettings) {
        guard let location = settings.location else { return nil }
        self.init(
            coordinates: location.coordinates,
            timeZone: location.timeZone,
            parameters: settings.calculationParameters
        )
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Returns nil where Adhan cannot resolve the day, such as polar latitudes.
    public func schedule(for date: Date) -> DaySchedule? {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        guard let times = PrayerTimes(coordinates: coordinates, date: day, calculationParameters: parameters) else {
            return nil
        }
        return DaySchedule(day: day, times: times)
    }

    public func schedule(dayOffset: Int, from date: Date) -> DaySchedule? {
        guard let shifted = calendar.date(byAdding: .day, value: dayOffset, to: date) else { return nil }
        return schedule(for: shifted)
    }

    public func moment(at now: Date) -> PrayerMoment? {
        guard let today = schedule(for: now) else { return nil }
        if now < today.fajr {
            guard let yesterday = schedule(dayOffset: -1, from: now) else { return nil }
            return PrayerMoment(current: .isha, currentStart: yesterday.isha, next: .fajr, nextTime: today.fajr)
        }
        let entries = today.entries
        let index = entries.lastIndex { $0.time <= now } ?? 0
        let current = entries[index]
        if index + 1 < entries.count {
            let next = entries[index + 1]
            return PrayerMoment(current: current.prayer, currentStart: current.time, next: next.prayer, nextTime: next.time)
        }
        guard let tomorrow = schedule(dayOffset: 1, from: now) else { return nil }
        return PrayerMoment(current: .isha, currentStart: today.isha, next: .fajr, nextTime: tomorrow.fajr)
    }

    public func isFriday(_ date: Date) -> Bool {
        calendar.component(.weekday, from: date) == 6
    }
}
