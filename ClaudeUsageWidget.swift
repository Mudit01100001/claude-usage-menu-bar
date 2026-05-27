import WidgetKit
import SwiftUI
import Foundation

// MARK: - Shared Data Model

struct SharedUsageInfo: Codable {
    let sessionUtilization: Double
    let sessionTimeRemaining: String
    let weeklyUtilization: Double
    let weeklyTimeRemaining: String
}

// MARK: - Timeline Entry

struct ClaudeUsageEntry: TimelineEntry {
    let date: Date
    let sessionUtilization: Double
    let sessionTimeRemaining: String
    let weeklyUtilization: Double
    let weeklyTimeRemaining: String
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    typealias Entry = ClaudeUsageEntry
    
    private func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.Mudit01100001.claude-usage")
    }
    
    private func placeholderEntry() -> ClaudeUsageEntry {
        ClaudeUsageEntry(
            date: Date(),
            sessionUtilization: 0.0,
            sessionTimeRemaining: "No data",
            weeklyUtilization: 0.0,
            weeklyTimeRemaining: "No data"
        )
    }
    
    func placeholder(in context: Context) -> ClaudeUsageEntry {
        ClaudeUsageEntry(
            date: Date(),
            sessionUtilization: 65.0,
            sessionTimeRemaining: "2h 21m left",
            weeklyUtilization: 18.0,
            weeklyTimeRemaining: "4d 17h left"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> ()) {
        completion(loadEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> ()) {
        let entry = loadEntry()
        // Refresh every 5 minutes dynamically as backup, but the main app will force reload immediately on fetch
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadEntry() -> ClaudeUsageEntry {
        guard let containerURL = getSharedContainerURL() else {
            return placeholderEntry()
        }
        let fileURL = containerURL.appendingPathComponent("usage.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            let info = try JSONDecoder().decode(SharedUsageInfo.self, from: data)
            return ClaudeUsageEntry(
                date: Date(),
                sessionUtilization: info.sessionUtilization,
                sessionTimeRemaining: info.sessionTimeRemaining,
                weeklyUtilization: info.weeklyUtilization,
                weeklyTimeRemaining: info.weeklyTimeRemaining
            )
        } catch {
            return placeholderEntry()
        }
    }
}

// MARK: - Circular Progress Ring View

struct CircularProgressRing: View {
    let progress: Double
    
    var color: Color {
        if progress >= 80 {
            return .red
        } else if progress >= 60 {
            return .orange
        } else {
            return .green
        }
    }
    
    var body: some View {
        ZStack {
            // Background Track Circle
            Circle()
                .stroke(lineWidth: 3.5)
                .opacity(0.12)
                .foregroundColor(color)
            
            // Foreground Trimmed Progress Circle
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress / 100.0, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(Angle(degrees: -90)) // Start stroke from top (12 o'clock)
            
            // Centered Text Percentage
            Text("\(Int(progress))%")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - Widget View Layout

struct ClaudeUsageWidgetEntryView : View {
    var entry: Provider.Entry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Session Limit
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Limit")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(entry.sessionTimeRemaining)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
                CircularProgressRing(progress: entry.sessionUtilization)
            }
            
            Divider()
                .opacity(0.2)
            
            // Row 2: Weekly Limit
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Limit")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(entry.weeklyTimeRemaining)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
                CircularProgressRing(progress: entry.weeklyUtilization)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color(NSColor.windowBackgroundColor).opacity(0.5)
        }
    }
}

// MARK: - Widget Main Entry Point

@main
struct ClaudeUsageWidget: Widget {
    let kind: String = "ClaudeUsageWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ClaudeUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Track your rolling Claude session limits and weekly usage on your desktop.")
        .supportedFamilies([.systemSmall])
    }
}
