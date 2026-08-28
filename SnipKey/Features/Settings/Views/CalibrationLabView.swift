//
//  CalibrationLabView.swift
//  SnipKey
//
//  DEBUG-only calibration workflow (V2_KEYBOARD_NEXTGEN_PLAN §11/§15):
//   1. CalibrationDrillView — type scripted phrases with the SnipKey keyboard while
//      Calibration Capture records full-fidelity tap sessions to the App Group.
//   2. ReplayLabView — re-run captured sessions through the resolver under a parameter
//      sweep and rank the variants (accuracy / harm / rescue on resolver-independent
//      labels, plus the baseline bit-exactness gate).
//
//  Sessions record typed text — developer-device tool, never shipped (RELEASE locks the
//  capture flag off and these screens are compiled out).
//

#if DEBUG
import SwiftUI

// MARK: - Drill

struct CalibrationDrillView: View {
    /// MacKenzie–Soukoreff phrase-set subset (memorable, letters-only, no punctuation) —
    /// the standard corpus for typing studies. Labels don't depend on the phrase (the
    /// harness derives them from geometry + backspace-retype patterns); the script just
    /// standardizes volume and regimes.
    private static let phrases = [
        "the quick brown fox jumps over the lazy dog",
        "video camera with a zoom lens",
        "have a good weekend",
        "what you see is what you get",
        "important news always seems to be late",
        "the back yard of our house is beautiful",
        "prevailing wind from the east",
        "an offer you cannot refuse",
        "a quarter of a century",
        "the store will close at ten",
        "flashing red light means stop",
        "my bike has a flat tire",
        "do not walk too quickly",
        "our fax number has changed",
        "please provide your date of birth",
        "we accumulated our wealth slowly",
        "this watch is too expensive",
        "the postal service is very slow",
        "communicate through electronic mail",
        "the capital of our nation",
        "travel at the speed of light",
        "i can see the rings on saturn",
        "this is a very good idea",
        "a problem with the engine",
        "elephants are afraid of mice",
        "my favorite subject is psychology",
        "circumstances are unacceptable",
        "watch out for low flying objects",
        "if at first you do not succeed",
        "electric cars need big batteries",
        "the fire raged for an entire month",
        "one hour is allotted for questions",
        "the minimum amount of time",
        "a fox is a very cunning creature",
        "the sun rises in the east",
        "it is very windy today",
        "do not say anything at all",
        "playing games can be fun",
        "great disturbance in the force",
        "the world is a stage",
    ]

    private static let regimes = [
        ("Relaxed", "Type normally, correct mistakes as you notice them."),
        ("Fast", "Type as fast as you can — accuracy will suffer, that's the point."),
        ("One-handed", "Thumb-type with one hand only."),
    ]

    @State private var phraseIndex = 0
    @State private var regimeIndex = 0
    @State private var typed = ""
    @State private var captureOn = AppGroupSettings.bool(
        forKey: AppGroupSettings.Key.calibrationCaptureEnabled, default: false)

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $captureOn) {
                    Text("Calibration Capture")
                        .font(.custom("IBMPlexMono-Medium", size: 15))
                }
                .tint(.purple)
                .onChange(of: captureOn) { _, newValue in
                    AppGroupSettings.setBool(newValue, forKey: AppGroupSettings.Key.calibrationCaptureEnabled)
                }
            } footer: {
                Text("Records raw taps AND typed characters to the App Group (this device only). Reopen the keyboard after toggling. Sessions flush when the keyboard closes — switch apps or dismiss the keyboard between regimes.")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
            }

            Section {
                let regime = Self.regimes[regimeIndex]
                Text(regime.0).font(.custom("IBMPlexMono-Medium", size: 15))
                Text(regime.1)
                    .font(.custom("IBMPlexMono-Regular", size: 12))
                    .foregroundColor(.secondary)
                Picker("Regime", selection: $regimeIndex) {
                    ForEach(0..<Self.regimes.count, id: \.self) { i in
                        Text(Self.regimes[i].0).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Regime")
            }

            Section {
                Text(Self.phrases[phraseIndex])
                    .font(.custom("IBMPlexMono-Medium", size: 16))
                    .padding(.vertical, 4)
                TextField("Type the phrase here with the SnipKey keyboard", text: $typed, axis: .vertical)
                    .font(.custom("IBMPlexMono-Regular", size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Button("Next Phrase") {
                        phraseIndex = (phraseIndex + 1) % Self.phrases.count
                        typed = ""
                    }
                    Spacer()
                    Text("\(phraseIndex + 1)/\(Self.phrases.count)")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Phrase")
            } footer: {
                Text("Aim for all \(Self.phrases.count) phrases per regime (~2,500 taps total). Use the SnipKey keyboard, on a real device — simulator taps carry no touch-offset signal.")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
            }
        }
        .navigationTitle("Calibration Drill")
    }
}

// MARK: - Replay Lab

struct ReplayLabView: View {
    struct SessionRow: Identifiable {
        let id = UUID()
        let url: URL
        let taps: Int
        let date: Date
        var selected = true
    }

    @State private var sessions: [SessionRow] = []
    @State private var results: [ResolverReplayEngine.Metrics] = []
    @State private var baselineGate: String?
    @State private var running = false
    @State private var exportText: String?

    var body: some View {
        Form {
            Section {
                if sessions.isEmpty {
                    Text("No captured sessions. Run the Calibration Drill first.")
                        .font(.custom("IBMPlexMono-Regular", size: 13))
                        .foregroundColor(.secondary)
                }
                ForEach($sessions) { $row in
                    Toggle(isOn: $row.selected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.custom("IBMPlexMono-Medium", size: 13))
                            Text("\(row.taps) taps")
                                .font(.custom("IBMPlexMono-Regular", size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.purple)
                }
            } header: {
                Text("Sessions")
            }

            Section {
                Button(running ? "Running…" : "Run Parameter Sweep") {
                    runSweep()
                }
                .disabled(running || sessions.allSatisfy { !$0.selected })
                if let gate = baselineGate {
                    Text(gate)
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                        .foregroundColor(gate.hasPrefix("PASS") ? .green : .red)
                }
            } footer: {
                Text("The baseline variant must reproduce the live decisions bit-exact (the harness gate). Decision rules for adopting a winner: accuracy up, harm rate NOT up, slow-bucket accuracy unchanged.")
                    .font(.custom("IBMPlexMono-Regular", size: 11))
            }

            if !results.isEmpty {
                Section {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name)
                                .font(.custom("IBMPlexMono-Medium", size: 13))
                            Text(String(format: "acc %.1f%%  harm %.2f%%  rescue %.2f%%  slow %.1f%%  n=%d",
                                        m.accuracy * 100, m.harmRate * 100, m.rescueRate * 100,
                                        m.slowAccuracy * 100, m.labeled))
                                .font(.custom("IBMPlexMono-Regular", size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Results (ranked by accuracy, harm-safe first)")
                }

                if let exportText {
                    Section {
                        ShareLink(item: exportText) {
                            Text("Export CSV")
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                        }
                    }
                }
            }
        }
        .navigationTitle("Replay Lab")
        .onAppear(perform: loadSessions)
    }

    private func loadSessions() {
        sessions = CalibrationCapture.sessionURLs().compactMap { url in
            guard let session = CalibrationCapture.loadSession(at: url) else { return nil }
            return SessionRow(url: url,
                              taps: session.taps.count,
                              date: Date(timeIntervalSince1970: session.header.capturedAtEpoch))
        }
    }

    private func runSweep() {
        running = true
        results = []
        baselineGate = nil
        let urls = sessions.filter(\.selected).map(\.url)
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = urls.compactMap { CalibrationCapture.loadSession(at: $0) }
            guard let first = loaded.first else {
                DispatchQueue.main.async { running = false }
                return
            }
            let base = ResolverReplayEngine.Variant.baseline(of: first.header)
            let variants = ResolverReplayEngine.standardSweep(around: base)
            var metrics = ResolverReplayEngine.sweep(sessions: loaded, variants: variants)

            // Harness gate: the baseline must reproduce live decisions bit-exact.
            let gate: String
            if let baseline = metrics.first(where: { $0.name == "baseline" }) {
                let rate = baseline.actingMatchRate
                gate = rate >= 0.9999
                    ? String(format: "PASS — baseline reproduces %.2f%% of live decisions", rate * 100)
                    : String(format: "FAIL — baseline matches only %.2f%% of live decisions; sweep results untrustworthy", rate * 100)
            } else {
                gate = "FAIL — no baseline variant ran"
            }

            // Rank: harm-safe variants first (harm ≤ baseline), then accuracy.
            let baselineHarm = metrics.first(where: { $0.name == "baseline" })?.harmRate ?? 0
            metrics.sort {
                let aSafe = $0.harmRate <= baselineHarm + 0.0001
                let bSafe = $1.harmRate <= baselineHarm + 0.0001
                if aSafe != bSafe { return aSafe }
                return $0.accuracy > $1.accuracy
            }

            var csv = "variant,charTaps,actingMatch,labeled,accuracy,harmRate,rescueRate,slowAccuracy\n"
            for m in metrics {
                csv += "\(m.name),\(m.charTaps),\(m.matchedActing),\(m.labeled),"
                csv += String(format: "%.4f,%.4f,%.4f,%.4f\n", m.accuracy, m.harmRate, m.rescueRate, m.slowAccuracy)
            }

            DispatchQueue.main.async {
                self.results = metrics
                self.baselineGate = gate
                self.exportText = csv
                self.running = false
            }
        }
    }
}
#endif
