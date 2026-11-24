import SwiftUI

// MARK: - Battery & thermal page (read-only)
//
// Shows battery health, cycle count, temperature and thermal
// history from the system powerlog. All strings are English,
// like the rest of the app.

struct BatteryDiagnosticsView: View {
    @StateObject private var manager = BatteryDiagnostics()

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: "About this feature", footer: "Read-only: the powerlog is cloned into this app's temp folder and inspected there. Nothing is ever written to the system database. Some iOS 26 firmware restricts the powerlog sandbox token; iOS 27 reads fully.") {
                Text("Battery & Thermal reads the system powerlog database: battery level, true health (raw max vs design capacity), cycle count, cell temperature, and thermal history. Values come from the latest samples in the log, newest first.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            WTSectionCard(header: "Live thermal state") {
                HStack {
                    Text("This device right now")
                        .font(.subheadline)
                    Spacer()
                    Text(manager.liveThermalState)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            WTSectionCard(header: "Read") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            SoundEffects.playTap()
                            manager.load()
                        } label: {
                            Label(manager.isLoading ? "Reading…" : "Read Powerlog", systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isLoading)
                        Spacer(minLength: 0)
                        if manager.isLoading {
                            ProgressView()
                        }
                    }
                    switch manager.state {
                    case .idle:
                        Text("Tap Read Powerlog to load the latest battery samples.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .loading:
                        Text("Cloning the powerlog and reading its latest samples…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .ready:
                        Text("Read complete\(manager.batteryTableUsed.map { " — battery table \($0)" } ?? "")\(manager.thermalTableUsed.map { ", thermal table \($0)" } ?? "").")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .blocked(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if case .ready = manager.state {
                if let latest = manager.latest {
                    WTSectionCard(header: "Latest sample") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let level = latest.level {
                                sampleRow("Level", String(format: "%.0f%%", level))
                            }
                            if let health = latest.healthPercent {
                                sampleRow("True health", String(format: "%.1f%%", health))
                            }
                            if let raw = latest.rawMaxCapacity {
                                sampleRow("Raw max capacity", String(format: "%.0f mAh", raw))
                            }
                            if let design = latest.designCapacity {
                                sampleRow("Design capacity", String(format: "%.0f mAh", design))
                            }
                            if let nominal = latest.nominalCapacity {
                                sampleRow("Nominal capacity", String(format: "%.0f mAh", nominal))
                            }
                            if let cycles = latest.cycleCount {
                                sampleRow("Cycle count", "\(cycles)")
                            }
                            if let temp = latest.temperature {
                                sampleRow("Cell temperature", String(format: "%.1f °C", temp))
                            }
                            if let volts = latest.voltage {
                                sampleRow("Voltage", String(format: "%.0f mV", volts))
                            }
                            if let amps = latest.amperage {
                                sampleRow("Amperage", String(format: "%.0f mA", amps))
                            }
                            if let watts = latest.powerWatts {
                                sampleRow("Power", String(format: "%.2f W", watts))
                            }
                            if let charging = latest.isCharging {
                                sampleRow("Charging", charging ? "Yes" : "No")
                            }
                            if let time = latest.timestamp {
                                sampleRow("Sampled", time.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                if !manager.samples.isEmpty {
                    WTSectionCard(header: "Recent samples (\(manager.samples.count))") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(manager.samples.enumerated()), id: \.element.id) { index, sample in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(sample.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown time")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        if let level = sample.level {
                                            Text(String(format: "%.0f%%", level))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    HStack(spacing: 12) {
                                        if let health = sample.healthPercent {
                                            Text(String(format: "Health %.1f%%", health))
                                        }
                                        if let cycles = sample.cycleCount {
                                            Text("\(cycles) cycles")
                                        }
                                        if let temp = sample.temperature {
                                            Text(String(format: "%.1f °C", temp))
                                        }
                                        if let charging = sample.isCharging, charging {
                                            Text("Charging")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                if index < manager.samples.count - 1 {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                    }
                }

                WTSectionCard(header: "Thermal history (\(manager.thermalEvents.count))") {
                    VStack(alignment: .leading, spacing: 0) {
                        if manager.thermalEvents.isEmpty {
                            Text("No thermal events found in the powerlog.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(Array(manager.thermalEvents.enumerated()), id: \.element.id) { index, event in
                                HStack {
                                    Text(event.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown time")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(event.band) (\(event.level))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(event.level > 20 ? .red : event.level > 10 ? .orange : .secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                if index < manager.thermalEvents.count - 1 {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Battery & Thermal")
        .onAppear {
            if case .idle = manager.state {
                manager.load()
            }
        }
    }

    private func sampleRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}
