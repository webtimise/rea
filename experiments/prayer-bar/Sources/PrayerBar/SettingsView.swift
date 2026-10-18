import Adhan
import AppKit
import PrayerKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            LocationSettings().tabItem { Label("Location", systemImage: "location") }
            CalculationSettings().tabItem { Label("Calculation", systemImage: "function") }
            NotificationSettingsView().tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 460, height: 420)
        // Menu bar apps are not activated by SettingsLink, so the window
        // would otherwise open behind the frontmost app.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct LocationSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var results: [CityResult] = []
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Current") {
                LabeledContent("Location", value: model.settings.location?.name ?? "Not set")
                if let status = model.locationStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Button("Use My Location") { model.useDeviceLocation() }
            }
            Section("Search") {
                HStack {
                    TextField("City, e.g. Cairo or London", text: $query)
                        .onSubmit(search)
                    Button("Search", action: search).disabled(searching)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(results) { city in
                    Button {
                        model.useCity(city)
                        results = []
                    } label: {
                        VStack(alignment: .leading) {
                            Text(city.name)
                            Text(city.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("General") {
                Toggle("Use 24-hour clock", isOn: $model.settings.use24HourClock)
                Toggle("Open at login", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private func search() {
        let text = query
        searching = true
        message = nil
        Task {
            do {
                results = try await model.citySearch.search(text)
                if results.isEmpty { message = "No matches. Try adding the country name." }
            } catch {
                message = "Search failed. Check your connection."
            }
            searching = false
        }
    }
}

private struct CalculationSettings: View {
    @EnvironmentObject private var model: AppModel

    private var method: Binding<CalculationMethod> {
        Binding(get: { model.settings.method }, set: { model.setMethod($0) })
    }

    var body: some View {
        Form {
            Section("Method") {
                Picker("Method", selection: method) {
                    ForEach(CalculationMethod.selectable, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Asr", selection: $model.settings.madhab) {
                    Text("Shafi, Maliki, Hanbali").tag(Madhab.shafi)
                    Text("Hanafi").tag(Madhab.hanafi)
                }
                Picker("High latitudes", selection: $model.settings.highLatitudeRule) {
                    Text("Automatic").tag(HighLatitudeRule?.none)
                    Text("Middle of the night").tag(HighLatitudeRule?.some(.middleOfTheNight))
                    Text("Seventh of the night").tag(HighLatitudeRule?.some(.seventhOfTheNight))
                    Text("Twilight angle").tag(HighLatitudeRule?.some(.twilightAngle))
                }
                if model.settings.method == .moonsightingCommittee {
                    Picker("Isha twilight", selection: $model.settings.shafaq) {
                        Text("General").tag(Shafaq.general)
                        Text("Red (Ahmer)").tag(Shafaq.ahmer)
                        Text("White (Abyad)").tag(Shafaq.abyad)
                    }
                }
            }
            Section("Adjustments (minutes)") {
                ForEach(PrayerName.allCases, id: \.self) { prayer in
                    let minutes = model.settings.adjustments[keyPath: prayer.adjustment]
                    Stepper(value: adjustment(prayer), in: -30...30) {
                        LabeledContent(prayer.displayName, value: minutes > 0 ? "+\(minutes)" : "\(minutes)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func adjustment(_ prayer: PrayerName) -> Binding<Int> {
        Binding(
            get: { model.settings.adjustments[keyPath: prayer.adjustment] },
            set: { model.settings.adjustments[keyPath: prayer.adjustment] = $0 }
        )
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Toggle("Notifications", isOn: $model.settings.notifications.enabled)
            Section("At prayer time") {
                ForEach(PrayerName.prayers, id: \.self) { prayer in
                    Toggle(prayer.displayName, isOn: membership(\.atTime, prayer))
                }
                Toggle("Call Friday Dhuhr Jumu'ah", isOn: $model.settings.notifications.jumuahOnFriday)
            }
            Section("Reminder before") {
                Stepper(value: $model.settings.notifications.reminderLeadMinutes, in: 5...60, step: 5) {
                    LabeledContent("Lead time", value: "\(model.settings.notifications.reminderLeadMinutes) min")
                }
                ForEach(PrayerName.prayers, id: \.self) { prayer in
                    Toggle(prayer.displayName, isOn: membership(\.reminders, prayer))
                }
            }
            Section("Duha") {
                Toggle("Remind me after sunrise", isOn: $model.settings.notifications.duha)
                Stepper(value: $model.settings.notifications.duhaMinutesAfterSunrise, in: 15...60, step: 5) {
                    LabeledContent("Minutes after sunrise", value: "\(model.settings.notifications.duhaMinutesAfterSunrise)")
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.settings.location == nil)
    }

    private func membership(_ set: WritableKeyPath<NotificationSettings, Set<PrayerName>>, _ prayer: PrayerName) -> Binding<Bool> {
        Binding(
            get: { model.settings.notifications[keyPath: set].contains(prayer) },
            set: { on in
                if on {
                    model.settings.notifications[keyPath: set].insert(prayer)
                } else {
                    model.settings.notifications[keyPath: set].remove(prayer)
                }
            }
        )
    }
}

private extension PrayerName {
    var adjustment: WritableKeyPath<PrayerAdjustments, Int> {
        switch self {
        case .fajr: \.fajr
        case .sunrise: \.sunrise
        case .dhuhr: \.dhuhr
        case .asr: \.asr
        case .maghrib: \.maghrib
        case .isha: \.isha
        }
    }
}
