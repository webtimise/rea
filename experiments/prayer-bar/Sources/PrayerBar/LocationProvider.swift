import CoreLocation
import PrayerKit

/// Device location plus reverse geocoding for a display name, country (for
/// regional method defaults) and the place's time zone.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var onResolved: ((SavedLocation) -> Void)?
    var onFailure: ((String) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    /// Authorization callbacks also fire at startup; only an explicit
    /// refresh may replace a manually chosen city.
    private var wantsFix = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        wantsFix = true
        requestIfAuthorized(prompt: true)
    }

    func resolve(city: CityResult) async -> SavedLocation {
        let placemark = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: city.latitude, longitude: city.longitude)
        ).first
        return SavedLocation(
            latitude: city.latitude,
            longitude: city.longitude,
            name: city.name,
            countryCode: city.countryCode ?? placemark?.isoCountryCode,
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
            source: .manual
        )
    }

    private func requestIfAuthorized(prompt: Bool) {
        guard wantsFix else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            if prompt { manager.requestWhenInUseAuthorization() }
        case .denied, .restricted:
            wantsFix = false
            onFailure?("Location access is off. Search for a city instead.")
        default:
            manager.requestLocation()
        }
    }

    private func resolveDevice(latitude: Double, longitude: Double) async {
        let placemark = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: latitude, longitude: longitude)
        ).first
        let name = placemark?.locality ?? placemark?.administrativeArea ?? placemark?.country ?? "Current location"
        onResolved?(SavedLocation(
            latitude: latitude,
            longitude: longitude,
            name: name,
            countryCode: placemark?.isoCountryCode,
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
            source: .device
        ))
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.requestIfAuthorized(prompt: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor in
            guard self.wantsFix else { return }
            self.wantsFix = false
            await self.resolveDevice(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.wantsFix = false
            self.onFailure?("Couldn't get your location: \(message)")
        }
    }
}
