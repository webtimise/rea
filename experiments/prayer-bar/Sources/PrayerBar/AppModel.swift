import Adhan
import AppKit
import Combine
import CoreLocation
import PrayerKit
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: PrayerSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            recompute()
            if settings.notifications != oldValue.notifications || settings.location != oldValue.location
                || settings.calculationParameters != oldValue.calculationParameters {
                rescheduleNotifications()
            }
        }
    }

    @Published private(set) var now = Date()
    @Published private(set) var today: DaySchedule?
    @Published private(set) var moment: PrayerMoment?
    @Published private(set) var locationStatus: String?
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet { updateLaunchAtLogin() }
    }

    let citySearch = CitySearch(userAgent: "PrayerBar/0.1 (personal prayer times app)")

    private static let settingsKey = "settings.v1"
    private let defaults = UserDefaults.standard
    private let location = LocationProvider()
    private let notifications = NotificationScheduler()
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(PrayerSettings.self, from: data) {
            settings = saved
        } else {
            settings = PrayerSettings()
        }

        location.onResolved = { [weak self] resolved in
            self?.locationStatus = nil
            self?.settings.apply(location: resolved)
        }
        location.onFailure = { [weak self] message in
            self?.locationStatus = message
        }

        recompute()
        startTicking()
        observeSystemChanges()
        if settings.location == nil || settings.location?.source == .device {
            location.refresh()
        }
        Task {
            await notifications.requestAuthorization()
            rescheduleNotifications()
        }
    }

    var calculator: PrayerCalculator? { PrayerCalculator(settings: settings) }

    var menuBarTitle: String {
        guard let moment else { return settings.location == nil ? "Set location" : "—" }
        return "\(moment.next.displayName) \(PrayerFormat.countdown(from: now, to: moment.nextTime))"
    }

    func formatted(_ date: Date) -> String {
        PrayerFormat.time(date, in: settings.location?.timeZone ?? .current, use24Hour: settings.use24HourClock)
    }

    func useDeviceLocation() {
        locationStatus = "Locating…"
        location.refresh()
    }

    func useCity(_ city: CityResult) {
        Task {
            let resolved = await location.resolve(city: city)
            settings.apply(location: resolved)
        }
    }

    func setMethod(_ method: CalculationMethod) {
        settings.method = method
        settings.hasChosenMethod = true
    }

    // MARK: - Private

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    private func recompute() {
        now = Date()
        guard let calculator else {
            today = nil
            moment = nil
            return
        }
        today = calculator.schedule(for: now)
        let previous = moment?.current
        moment = calculator.moment(at: now)
        // Each boundary crossing extends the planned window by another prayer.
        if let previous, previous != moment?.current {
            rescheduleNotifications()
        }
    }

    private func rescheduleNotifications() {
        guard let calculator else { return }
        let plan = NotificationPlanner.plan(calculator: calculator, settings: settings.notifications, from: Date())
        notifications.replace(with: plan)
    }

    private func startTicking() {
        // Re-evaluate every 15 seconds so the countdown and segment stay
        // current; the timer tolerance lets macOS coalesce wakeups.
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func observeSystemChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.recompute()
                self?.rescheduleNotifications()
            }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.recompute()
                    self?.rescheduleNotifications()
                }
            })
        }
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PrayerBar: launch at login change failed: \(error.localizedDescription)")
        }
    }
}
