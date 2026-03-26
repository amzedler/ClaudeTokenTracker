import SwiftUI
import Charts
import AppKit

@main
struct ClaudeTokenTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty settings scene — all UI driven by AppDelegate
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate (NSStatusItem for plain menu bar text)

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var loader = TokenDataLoader()
    private var observation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "$0.00"
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 580)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DropdownView(loader: loader)
        )

        // Observe loader changes to update button title
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.statusItem.button?.title = self.loader.formattedSevenDayCost
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - Dropdown

struct DropdownView: View {
    @ObservedObject var loader: TokenDataLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 7-day summary header
            SevenDaySummary(loader: loader)

            // Daily cost chart
            DailyCostChart(days: loader.dailyUsage)

            Divider().padding(.horizontal, 12)

            // Current session
            if loader.isActive || loader.current.costUsd > 0 {
                CurrentSessionSection(data: loader.current, isActive: loader.isActive)
                Divider().padding(.horizontal, 12)
            }

            // Session history
            SessionListSection(sessions: loader.sessions)

            Divider().padding(.horizontal, 12).padding(.top, 4)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

// MARK: - 7-Day Summary

struct SevenDaySummary: View {
    @ObservedObject var loader: TokenDataLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trailing 7 Days")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(loader.trailingSevenDaySessions) sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COST")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(loader.formattedSevenDayCost)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TOKENS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(TokenData.formatTokens(loader.trailingSevenDayTokens))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Daily Cost Chart

struct DailyCostChart: View {
    let days: [DailyUsage]

    var maxCost: Double {
        max(days.map(\.cost).max() ?? 1, 0.01)
    }

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.label),
                y: .value("Cost", day.cost)
            )
            .foregroundStyle(
                day.label == "Today"
                    ? Color.accentColor
                    : Color.primary.opacity(0.25)
            )
            .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "$%.0f", v))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(.quaternary)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxCost * 1.15)
        .frame(height: 90)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Current Session

struct CurrentSessionSection: View {
    let data: TokenData
    let isActive: Bool

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    if isActive {
                        Circle().fill(.green).frame(width: 6, height: 6)
                    }
                    Text("Current Session")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(data.formattedCost)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text(data.model)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if expanded {
                VStack(spacing: 0) {
                    StatRow(label: "Input", value: data.formattedInputTokens)
                    StatRow(label: "Output", value: data.formattedOutputTokens)
                    StatRow(label: "Cache Read", value: data.formattedCacheRead)
                    StatRow(label: "Cache Write", value: data.formattedCacheWrite)
                    StatRow(label: "Wall Time", value: data.formattedDuration)
                    StatRow(label: "API Time", value: data.formattedApiDuration)

                    ContextBar(percentage: data.contextPercentInt)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Session List

struct SessionListSection: View {
    let sessions: [TokenData]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT SESSIONS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if sessions.isEmpty {
                Text("No previous sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(50).enumerated()), id: \.offset) { _, session in
                            SessionRow(data: session)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 300)
            }
        }
    }
}

struct SessionRow: View {
    let data: TokenData

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.formattedSessionDate)
                            .font(.system(size: 11))
                        Text(data.model)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(data.formattedCost)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text(data.formattedTotalTokens + " tok")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            if expanded {
                VStack(spacing: 0) {
                    StatRow(label: "Input", value: data.formattedInputTokens)
                    StatRow(label: "Output", value: data.formattedOutputTokens)
                    StatRow(label: "Duration", value: data.formattedDuration)
                }
                .padding(.bottom, 4)
                .transition(.opacity)
            }

            Divider().padding(.horizontal, 20)
        }
    }
}

// MARK: - Shared Components

struct StatRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: highlight ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(highlight ? .primary : .secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 1)
    }
}

struct ContextBar: View {
    let percentage: Int

    var barColor: Color {
        if percentage >= 80 { return .red }
        if percentage >= 60 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(percentage) / 100, height: 5)
                }
            }
            .frame(height: 5)
            Text("\(percentage)%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}
