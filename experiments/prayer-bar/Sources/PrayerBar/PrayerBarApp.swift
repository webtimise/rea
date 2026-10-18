import PrayerKit
import SwiftUI

@main
struct PrayerBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
        } label: {
            Text(model.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

extension DaySegment {
    /// Sky colours standing in for the original's per-segment videos.
    var gradient: [Color] {
        switch self {
        case .fajrToSunrise: [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.85, green: 0.55, blue: 0.55)]
        case .sunriseToDhuhr: [Color(red: 0.98, green: 0.76, blue: 0.47), Color(red: 0.47, green: 0.71, blue: 0.93)]
        case .dhuhrToAsr: [Color(red: 0.31, green: 0.62, blue: 0.94), Color(red: 0.62, green: 0.83, blue: 0.98)]
        case .asrToMaghrib: [Color(red: 0.95, green: 0.68, blue: 0.35), Color(red: 0.80, green: 0.42, blue: 0.38)]
        case .maghribToIsha: [Color(red: 0.55, green: 0.27, blue: 0.45), Color(red: 0.18, green: 0.15, blue: 0.38)]
        case .ishaToFajr: [Color(red: 0.05, green: 0.07, blue: 0.18), Color(red: 0.13, green: 0.17, blue: 0.33)]
        }
    }
}
