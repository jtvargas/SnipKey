//
//  ShadowTelemetryView.swift
//  SnipKey
//
//  Host-app analysis screen for the Keyboard V2 shadow-mode telemetry. Reads the privacy-safe
//  `telemetry-shadow.json` the keyboard extension writes to the App Group container and turns
//  it into the numbers that gate the rollout and inform β / offset calibration
//  (V2_KEYBOARD_NEXTGEN_PLAN §11–§12):
//    • overall disagreement rate (new vs. legacy resolver)
//    • a per-key heatmap of disagreement rate
//    • the mean in-cell touch position — where users actually land within a key (0.5,0.5 =
//      center). A mean dy < 0.5 means people land in the upper half ⇒ tells us the offset sign.
//
//  All on-device. Nothing here leaves the phone.
//

import SwiftUI

struct ShadowTelemetryView: View {

    // Mirrors `TypingTelemetry.Event` / payload written by the keyboard extension.
    private struct Event: Codable {
        let layout: Int
        let actRow: Int
        let actCol: Int
        let shdRow: Int
        let shdCol: Int
        let agreed: Bool
        let dx: Float
        let dy: Float
    }
    private struct Payload: Codable {
        let total: Int
        let disagreements: Int
        let disagreementRate: Double
        let events: [Event]
        let outcomeTotal: Int?
        let unresolvedTouchDowns: Int?
        let rawResolvedDisagreements: Int?
        let outcomes: [TouchOutcome]?
    }

    private struct TouchOutcome: Codable {
        let layout: Int
        let rawRow: Int
        let rawCol: Int
        let resolvedRow: Int
        let resolvedCol: Int
        let runnerUpRow: Int?
        let runnerUpCol: Int?
        let resolvedDiffered: Bool
        let dx: Float
        let dy: Float
        let confidence: Float
        let margin: Float?
    }

    private struct CellStat: Identifiable {
        let id = UUID()
        let row: Int
        let col: Int
        var total: Int = 0
        var disagree: Int = 0
        var sumDx: Float = 0
        var sumDy: Float = 0
        var rate: Double { total > 0 ? Double(disagree) / Double(total) : 0 }
        var meanDx: Float { total > 0 ? sumDx / Float(total) : 0.5 }
        var meanDy: Float { total > 0 ? sumDy / Float(total) : 0.5 }
    }

    @State private var payload: Payload?
    @State private var loadError: String?

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.snipkey")?
            .appendingPathComponent("telemetry-shadow.json")
    }

    var body: some View {
        List {
            if let p = payload {
                summarySection(p)
                inCellSection(p)
                heatmapSection(p)
            } else {
                Section {
                    Text(loadError ?? "No telemetry yet. Enable “Shadow-Mode Logging,” type with the SnipKey keyboard, switch keyboards away, then come back and refresh.")
                        .font(.custom("IBMPlexMono-Regular", size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Shadow Telemetry")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { load() } label: { Image(systemName: "arrow.clockwise") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) { clear() } label: { Image(systemName: "trash") }
                    .disabled(payload == nil)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private func summarySection(_ p: Payload) -> some View {
        Section("Summary") {
            row("Touches sampled", "\(p.total)")
            row("Disagreements", "\(p.disagreements)")
            row("Disagreement rate", String(format: "%.2f%%", p.disagreementRate * 100))
            row("Touch outcomes", "\(p.outcomeTotal ?? 0)")
            row("Unresolved touch-downs", "\(p.unresolvedTouchDowns ?? 0)",
                tint: (p.unresolvedTouchDowns ?? 0) == 0 ? .green : .orange)
            row("Raw→resolved changes", "\(p.rawResolvedDisagreements ?? 0)")
            row("Mean confidence", String(format: "%.3f", meanConfidence(p)))
            row("Mean runner-up margin", String(format: "%.3f", meanMargin(p)))
            row("Rollout gate (< 3%)", p.disagreementRate < 0.03 ? "PASS" : "review",
                tint: p.disagreementRate < 0.03 ? .green : .orange)
        }
    }

    private func inCellSection(_ p: Payload) -> some View {
        let n = max(p.events.count, 1)
        let mdx = p.events.reduce(Float(0)) { $0 + $1.dx } / Float(n)
        let mdy = p.events.reduce(Float(0)) { $0 + $1.dy } / Float(n)
        return Section {
            row("Mean in-cell X", String(format: "%.3f (0.5 = center)", mdx))
            row("Mean in-cell Y", String(format: "%.3f (0.5 = center)", mdy))
            Text(mdy < 0.5
                 ? "Users land in the UPPER half of keys (dy<0.5) — offset correction should pull sites up."
                 : "Users land in the LOWER half of keys (dy>0.5) — offset correction should pull sites down.")
                .font(.custom("IBMPlexMono-Regular", size: 11))
                .foregroundColor(.secondary)
        } header: {
            Text("Touch landing (offset sign)")
        }
    }

    private func heatmapSection(_ p: Payload) -> some View {
        let cells = aggregate(p.events)
        let rows = Dictionary(grouping: cells, by: \.row).sorted { $0.key < $1.key }
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.key) { _, rowCells in
                    HStack(spacing: 4) {
                        ForEach(rowCells.sorted { $0.col < $1.col }) { c in
                            cellView(c)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            Text("Cell color = disagreement rate (green→red). Number = sample count.")
                .font(.custom("IBMPlexMono-Regular", size: 11))
                .foregroundColor(.secondary)
        } header: {
            Text("Per-key disagreement heatmap")
        }
    }

    private func cellView(_ c: CellStat) -> some View {
        let rate = c.rate
        return VStack(spacing: 1) {
            Text("\(c.total)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 28, height: 28)
        .background(
            Color(hue: 0.33 * (1 - rate), saturation: 0.85, brightness: 0.85)
        )
        .cornerRadius(5)
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label).font(.custom("IBMPlexMono-Regular", size: 14))
            Spacer()
            Text(value).font(.custom("IBMPlexMono-Medium", size: 14)).foregroundColor(tint)
        }
    }

    private func aggregate(_ events: [Event]) -> [CellStat] {
        var map: [String: CellStat] = [:]
        for e in events {
            let key = "\(e.actRow)-\(e.actCol)"
            var s = map[key] ?? CellStat(row: e.actRow, col: e.actCol)
            s.total += 1
            if !e.agreed { s.disagree += 1 }
            s.sumDx += e.dx
            s.sumDy += e.dy
            map[key] = s
        }
        return Array(map.values)
    }

    private func meanConfidence(_ payload: Payload) -> Float {
        guard let outcomes = payload.outcomes, !outcomes.isEmpty else { return 0 }
        return outcomes.reduce(Float(0)) { $0 + $1.confidence } / Float(outcomes.count)
    }

    private func meanMargin(_ payload: Payload) -> Float {
        let margins = payload.outcomes?.compactMap(\.margin) ?? []
        guard !margins.isEmpty else { return 0 }
        return margins.reduce(Float(0), +) / Float(margins.count)
    }

    private func load() {
        guard let url = fileURL else { loadError = "App Group container unavailable."; return }
        guard let data = try? Data(contentsOf: url) else {
            payload = nil; loadError = nil; return   // not an error — just no data yet
        }
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
            loadError = nil
        } catch {
            payload = nil
            loadError = "Could not read telemetry: \(error.localizedDescription)"
        }
    }

    private func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        payload = nil
        loadError = nil
    }
}
