import SwiftUI

struct HistoryListView: View {
    @EnvironmentObject var historyStore: HistoryStore
    @EnvironmentObject var historyViewModel: HistoryViewModel

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.entries.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zgodovina")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(
                get: { historyViewModel.selectedEntry != nil },
                set: { if !$0 { historyViewModel.selectedEntry = nil } }
            )) {
                if let entry = historyViewModel.selectedEntry {
                    HistoryDetailView(entry: entry)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Ni shranjenih posnetkov.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Posnetki in povzetki se samodejno shranijo po obdelavi.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(historyStore.entries) { entry in
                    historyCard(entry: entry)
                        .onTapGesture {
                            historyViewModel.selectEntry(entry)
                        }
                }
            }
            .padding()
        }
    }

    private func historyCard(entry: RecordingEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.summary?.summaries.first?.title ?? "Brez povzetka")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                if entry.isMeetingMode {
                    Text("Sestanek")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: 0.102, green: 0.451, blue: 0.910).opacity(0.15))
                        )
                        .foregroundStyle(Color(red: 0.102, green: 0.451, blue: 0.910))
                }

                Text(entry.summary != nil ? "Povzetek" : "Samo prepis")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(entry.summary != nil ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    )
                    .foregroundStyle(entry.summary != nil ? .green : .orange)
            }

            HStack(spacing: 4) {
                Text(formattedDate(entry.date))
                Text("·")
                Text(entry.duration)
                Text("·")
                Text(entry.language)
                if let summary = entry.summary {
                    Text("·")
                    Text(summary.modelName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(String(entry.transcript.prefix(100)) + (entry.transcript.count > 100 ? "..." : ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sl_SI")
        formatter.dateFormat = "d. MMM yyyy 'ob' HH:mm"
        return formatter.string(from: date)
    }
}
