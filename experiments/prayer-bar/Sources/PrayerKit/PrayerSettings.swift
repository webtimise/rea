import Adhan
import Foundation

public enum PrayerName: String, CaseIterable, Codable, Hashable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    public var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .sunrise: "Sunrise"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    /// Sunrise ends Fajr; it is not itself a prayer.
    public var isPrayer: Bool { self != .sunrise }

    public static let prayers: [PrayerName] = allCases.filter(\.isPrayer)

    var adhan: Prayer {
        switch self {
        case .fajr: .fajr
        case .sunrise: .sunrise
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }
}

public struct SavedLocation: Codable, Equatable {
    public enum Source: String, Codable {
        case device, manual
    }

    public var latitude: Double
    public var longitude: Double
    public var name: String
    public var countryCode: String?
    /// Prayer days follow the location's clock, not the Mac's, so a manually
    /// chosen city in another zone still gets that city's day.
    public var timeZoneIdentifier: String
    public var source: Source

    public init(
        latitude: Double,
        longitude: Double,
        name: String,
        countryCode: String?,
        timeZoneIdentifier: String,
        source: Source
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.countryCode = countryCode
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
    public var coordinates: Coordinates { Coordinates(latitude: latitude, longitude: longitude) }
}

public struct NotificationSettings: Codable, Equatable {
    public var enabled = true
    public var atTime: Set<PrayerName> = Set(PrayerName.prayers)
    public var reminders: Set<PrayerName> = []
    public var reminderLeadMinutes = 15
    public var jumuahOnFriday = true
    public var duha = false
    public var duhaMinutesAfterSunrise = 20

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotificationSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        atTime = try c.decodeIfPresent(Set<PrayerName>.self, forKey: .atTime) ?? d.atTime
        reminders = try c.decodeIfPresent(Set<PrayerName>.self, forKey: .reminders) ?? d.reminders
        reminderLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes) ?? d.reminderLeadMinutes
        jumuahOnFriday = try c.decodeIfPresent(Bool.self, forKey: .jumuahOnFriday) ?? d.jumuahOnFriday
        duha = try c.decodeIfPresent(Bool.self, forKey: .duha) ?? d.duha
        duhaMinutesAfterSunrise = try c.decodeIfPresent(Int.self, forKey: .duhaMinutesAfterSunrise) ?? d.duhaMinutesAfterSunrise
    }
}

public struct PrayerSettings: Codable, Equatable {
    public var method: CalculationMethod = .muslimWorldLeague
    /// False until the user picks a method, so a new location can still
    /// apply its regional default.
    public var hasChosenMethod = false
    public var madhab: Madhab = .shafi
    /// Nil follows Adhan's latitude-based recommendation.
    public var highLatitudeRule: HighLatitudeRule?
    public var shafaq: Shafaq = .general
    public var adjustments = PrayerAdjustments()
    public var use24HourClock = false
    public var notifications = NotificationSettings()
    public var location: SavedLocation?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrayerSettings()
        method = try c.decodeIfPresent(CalculationMethod.self, forKey: .method) ?? d.method
        hasChosenMethod = try c.decodeIfPresent(Bool.self, forKey: .hasChosenMethod) ?? d.hasChosenMethod
        madhab = try c.decodeIfPresent(Madhab.self, forKey: .madhab) ?? d.madhab
        highLatitudeRule = try c.decodeIfPresent(HighLatitudeRule.self, forKey: .highLatitudeRule)
        shafaq = try c.decodeIfPresent(Shafaq.self, forKey: .shafaq) ?? d.shafaq
        adjustments = try c.decodeIfPresent(PrayerAdjustments.self, forKey: .adjustments) ?? d.adjustments
        use24HourClock = try c.decodeIfPresent(Bool.self, forKey: .use24HourClock) ?? d.use24HourClock
        notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? d.notifications
        location = try c.decodeIfPresent(SavedLocation.self, forKey: .location)
    }

    public var calculationParameters: CalculationParameters {
        var params = method.params
        params.madhab = madhab
        if let highLatitudeRule {
            params.highLatitudeRule = highLatitudeRule
        }
        params.shafaq = shafaq
        params.adjustments = adjustments
        return params
    }

    /// Applies a location and, unless the user already chose a method,
    /// the method customary for its country.
    public mutating func apply(location: SavedLocation) {
        self.location = location
        if !hasChosenMethod {
            method = RegionalDefaults.method(forCountryCode: location.countryCode)
        }
    }
}

extension CalculationMethod {
    public static let selectable: [CalculationMethod] = allCases.filter { $0 != .other }

    public var displayName: String {
        switch self {
        case .muslimWorldLeague: "Muslim World League"
        case .egyptian: "Egyptian General Authority"
        case .karachi: "University of Islamic Sciences, Karachi"
        case .ummAlQura: "Umm al-Qura, Makkah"
        case .dubai: "Dubai"
        case .moonsightingCommittee: "Moonsighting Committee"
        case .northAmerica: "ISNA (North America)"
        case .kuwait: "Kuwait"
        case .qatar: "Qatar"
        case .singapore: "Singapore"
        case .tehran: "Institute of Geophysics, Tehran"
        case .turkey: "Diyanet, Turkey"
        case .other: "Custom"
        }
    }
}

public enum RegionalDefaults {
    public static func method(forCountryCode code: String?) -> CalculationMethod {
        switch (code ?? "").uppercased() {
        case "US", "CA", "GB": .moonsightingCommittee
        case "SA", "YE", "BH", "OM": .ummAlQura
        case "AE": .dubai
        case "QA": .qatar
        case "KW": .kuwait
        case "EG", "SD", "SY", "IQ", "LB", "LY", "JO", "PS": .egyptian
        case "PK", "IN", "BD", "AF": .karachi
        case "SG", "MY", "ID", "BN": .singapore
        case "IR": .tehran
        case "TR": .turkey
        default: .muslimWorldLeague
        }
    }
}
