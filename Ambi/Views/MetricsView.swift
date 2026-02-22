import SwiftUI

private struct MetricsData {
    var totalWords: Int = 0
    var totalSessions: Int = 0
    var currentStreak: Int = 0
    var wordsByDay: [(date: String, words: Int)] = []
    var wordsByHour: [Int: Int] = [:]
}

struct MetricsView: View {
    @State private var data = MetricsData()
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Loading metrics...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                } else {
                    statCards
                    weeklyChart
                    hourlyHeatmap
                }
            }
            .padding()
        }
        .task {
            await loadMetrics()
        }
    }

    // MARK: - Stat Cards

    private var statCards: some View {
        HStack(spacing: 12) {
            StatCard(label: "Total Words", value: "\(data.totalWords.formatted())", icon: "text.word.spacing")
            StatCard(label: "Sessions", value: "\(data.totalSessions)", icon: "calendar")
            StatCard(label: "Streak", value: "\(data.currentStreak) day\(data.currentStreak == 1 ? "" : "s")", icon: "flame.fill")
        }
    }

    // MARK: - 7-Day Bar Chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 Days")
                .font(.headline)

            if data.wordsByDay.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 80)
            } else {
                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(last7DayBars, id: \.date) { bar in
                            VStack(spacing: 4) {
                                Text("\(bar.words)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .opacity(bar.words > 0 ? 1 : 0)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.ambiAccent.opacity(0.7))
                                    .frame(width: (geo.size.width - 44) / 7,
                                           height: barHeight(for: bar.words, in: geo.size.height - 30))

                                Text(shortDay(bar.date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
                .frame(height: 110)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Hourly Heatmap

    private var hourlyHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hourly Activity")
                    .font(.headline)
                Spacer()
                if let peak = peakHour {
                    Text("Peak: \(hourLabel(peak))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.ambiAccent.opacity(hourOpacity(hour)))
                            .frame(width: (geo.size.width - 46) / 24,
                                   height: hourHeight(hour))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(height: 50)

            HStack {
                Text("12am")
                Spacer()
                Text("12pm")
                Spacer()
                Text("11pm")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Helpers

    private var last7DayBars: [(date: String, words: Int)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dataMap = Dictionary(data.wordsByDay.map { ($0.date, $0.words) }, uniquingKeysWith: { $1 })

        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let key = formatter.string(from: date)
            return (date: key, words: dataMap[key] ?? 0)
        }
    }

    private func barHeight(for words: Int, in maxHeight: CGFloat) -> CGFloat {
        let maxWords = last7DayBars.map { $0.words }.max() ?? 1
        guard maxWords > 0 else { return 4 }
        return max(4, CGFloat(words) / CGFloat(maxWords) * maxHeight)
    }

    private func shortDay(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return "?" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        return String(dayFormatter.string(from: date).prefix(3))
    }

    private var peakHour: Int? {
        data.wordsByHour.max(by: { $0.value < $1.value })?.key
    }

    private func hourOpacity(_ hour: Int) -> Double {
        let maxWords = data.wordsByHour.values.max() ?? 1
        let words = data.wordsByHour[hour] ?? 0
        guard maxWords > 0 else { return 0.1 }
        return 0.1 + 0.9 * Double(words) / Double(maxWords)
    }

    private func hourHeight(_ hour: Int) -> CGFloat {
        let maxWords = data.wordsByHour.values.max() ?? 1
        let words = data.wordsByHour[hour] ?? 0
        guard maxWords > 0 else { return 4 }
        return max(4, CGFloat(words) / CGFloat(maxWords) * 44)
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadMetrics() async {
        guard let db = try? DatabaseManager() else {
            isLoading = false
            return
        }
        let totalWords = (try? db.fetchTotalWordCount()) ?? 0
        let sessions = (try? db.fetchAllSessions()) ?? []
        let sessionDates = (try? db.fetchSessionDatesWithContent()) ?? []
        let wordsByDay = (try? db.fetchWordCountByDay(lastDays: 7)) ?? []
        let wordsByHour = (try? db.fetchWordCountByHour()) ?? [:]
        let streak = computeStreak(from: sessionDates)

        data = MetricsData(
            totalWords: totalWords,
            totalSessions: sessions.count,
            currentStreak: streak,
            wordsByDay: wordsByDay,
            wordsByHour: wordsByHour
        )
        isLoading = false
    }

    private func computeStreak(from dates: [Date]) -> Int {
        let calendar = Calendar.current
        let sortedDates = Set(dates.map { calendar.startOfDay(for: $0) })
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        while sortedDates.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.ambiAccent)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}

#Preview {
    MetricsView()
        .frame(width: 550, height: 400)
}
