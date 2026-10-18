import Foundation

public struct PlannedNotification: Equatable {
    public enum Kind: String {
        case atTime, reminder, duha
    }

    public static let identifierPrefix = "prayerbar."

    public let identifier: String
    public let kind: Kind
    public let prayer: PrayerName
    public let fireDate: Date
    public let title: String
    public let body: String
}

public enum NotificationPlanner {
    /// macOS keeps at most 64 pending requests per app.
    public static let pendingLimit = 64

    /// Plans every notification from `now` through the given number of
    /// location-local days, earliest first.
    public static func plan(
        calculator: PrayerCalculator,
        settings: NotificationSettings,
        from now: Date,
        days: Int = 2
    ) -> [PlannedNotification] {
        guard settings.enabled, days > 0 else { return [] }
        var planned: [PlannedNotification] = []

        for offset in 0..<days {
            guard let schedule = calculator.schedule(dayOffset: offset, from: now) else { continue }
            let friday = calculator.isFriday(schedule.dhuhr)
            let dayKey = String(
                format: "%04d-%02d-%02d",
                schedule.day.year ?? 0, schedule.day.month ?? 0, schedule.day.day ?? 0
            )

            func add(_ kind: PlannedNotification.Kind, _ prayer: PrayerName, _ date: Date, _ title: String, _ body: String) {
                guard date > now else { return }
                planned.append(PlannedNotification(
                    identifier: "\(PlannedNotification.identifierPrefix)\(dayKey).\(prayer.rawValue).\(kind.rawValue)",
                    kind: kind,
                    prayer: prayer,
                    fireDate: date,
                    title: title,
                    body: body
                ))
            }

            for prayer in PrayerName.prayers {
                let time = schedule.time(prayer)
                let name = (friday && settings.jumuahOnFriday && prayer == .dhuhr) ? "Jumu'ah" : prayer.displayName
                if settings.reminders.contains(prayer), settings.reminderLeadMinutes > 0 {
                    let lead = settings.reminderLeadMinutes
                    add(.reminder, prayer, time.addingTimeInterval(TimeInterval(-lead * 60)),
                        "\(name) in \(lead) minutes", "Time to get ready.")
                }
                if settings.atTime.contains(prayer) {
                    add(.atTime, prayer, time, name, "It's time for \(name).")
                }
            }

            if settings.duha {
                let start = schedule.sunrise.addingTimeInterval(TimeInterval(settings.duhaMinutesAfterSunrise * 60))
                if start < schedule.dhuhr {
                    add(.duha, .sunrise, start, "Duha", "Duha can be prayed until shortly before Dhuhr.")
                }
            }
        }

        planned.sort { $0.fireDate < $1.fireDate }
        return Array(planned.prefix(pendingLimit))
    }
}

public enum PrayerFormat {
    /// Remaining time rounded up to the minute, so a pending prayer never reads "0m".
    public static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(0, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours)h \(String(format: "%02d", rest))m" : "\(rest)m"
    }

    public static func time(_ date: Date, in timeZone: TimeZone, use24Hour: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}
