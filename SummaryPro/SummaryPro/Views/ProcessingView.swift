import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var recordingViewModel: RecordingViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text("Obdelava")
                    .font(.title2)
                    .fontWeight(.bold)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    stepRow(
                        label: "Prepisovanje govora...",
                        isActive: recordingViewModel.processingStep == .transcribing,
                        isDone: recordingViewModel.processingStep == .summarizing || recordingViewModel.processingStep == .generatingEmail
                    )
                    stepRow(
                        label: "AI povzemanje...",
                        isActive: recordingViewModel.processingStep == .summarizing,
                        isDone: recordingViewModel.processingStep == .generatingEmail
                    )
                    if recordingViewModel.isMeetingMode {
                        stepRow(
                            label: "Generiranje follow-up emaila...",
                            isActive: recordingViewModel.processingStep == .generatingEmail,
                            isDone: false
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )

                // Progress bar
                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: 0.102, green: 0.451, blue: 0.910))
                                .frame(width: geometry.size.width * recordingViewModel.progress, height: 8)
                                .animation(.easeInOut(duration: 0.3), value: recordingViewModel.progress)
                        }
                    }
                    .frame(height: 8)

                    Text(recordingViewModel.progressMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Spacer()
                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary Pro")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stepRow(label: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? .green : (isActive ? Color(red: 0.102, green: 0.451, blue: 0.910) : Color(.systemGray4)))
                    .frame(width: 24, height: 24)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else if isActive {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                }
            }

            Text(label)
                .font(.subheadline)
                .foregroundStyle(isActive || isDone ? .primary : .secondary)
        }
    }
}
