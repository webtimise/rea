import PrayerKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            if let moment = model.moment, let today = model.today {
                header(moment)
                VStack(spacing: 2) {
                    ForEach(PrayerName.allCases, id: \.self) { prayer in
                        row(prayer, time: today.time(prayer), moment: moment)
                    }
                }
            } else {
                missingLocation
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func header(_ moment: PrayerMoment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.settings.location?.name ?? "")
                .font(.caption)
                .opacity(0.8)
            Text("\(moment.next.displayName) in \(PrayerFormat.countdown(from: model.now, to: moment.nextTime))")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            ProgressView(value: moment.progress(at: model.now))
                .tint(.white)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(colors: moment.segment.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func row(_ prayer: PrayerName, time: Date, moment: PrayerMoment) -> some View {
        let isCurrent = prayer == moment.current && time == moment.currentStart
        return HStack {
            Text(prayer.displayName)
                .foregroundStyle(prayer.isPrayer ? Color.primary : Color.secondary)
            Spacer()
            Text(model.formatted(time))
                .monospacedDigit()
        }
        .fontWeight(isCurrent ? .semibold : .regular)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private var missingLocation: some View {
        VStack(spacing: 8) {
            Text(model.settings.location == nil ? "No location yet" : "Prayer times unavailable here")
                .font(.headline)
            if let status = model.locationStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Use My Location") { model.useDeviceLocation() }
            SettingsLink { Text("Search for a City…") }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
