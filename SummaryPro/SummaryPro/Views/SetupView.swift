import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var speechKey = ""
    @State private var openaiKey = ""
    @State private var sonioxKey = ""
    @State private var geminiKey = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    VStack(spacing: 16) {
                        apiKeyField(
                            label: "Google Speech-to-Text API",
                            hint: "(neobvezno)",
                            placeholder: "Google Cloud API ključ",
                            text: $speechKey
                        )

                        apiKeyField(
                            label: "OpenAI API",
                            hint: "(neobvezno, za Whisper STT)",
                            placeholder: "OpenAI API ključ",
                            text: $openaiKey
                        )

                        apiKeyField(
                            label: "Soniox API",
                            hint: "(neobvezno, za Soniox STT)",
                            placeholder: "Soniox API ključ",
                            text: $sonioxKey
                        )

                        Text("Potrebujete vsaj en STT ključ (Google, OpenAI ali Soniox).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        apiKeyField(
                            label: "Gemini API",
                            hint: nil,
                            placeholder: "Gemini API ključ",
                            text: $geminiKey
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    )

                    Button(action: saveKeys) {
                        Text("Shrani")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.102, green: 0.451, blue: 0.910))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary Pro")
            .alert("Napaka", isPresented: $showError) {
                Button("V redu", role: .cancel) {}
            } message: {
                Text("Vnesite vsaj en STT ključ in Gemini API ključ.")
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Nastavitve")
                .font(.title2)
                .fontWeight(.bold)
            Text("Vnesite API ključe. Shranjeni so varno v Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func apiKeyField(label: String, hint: String?, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func saveKeys() {
        let hasAnyStt = !speechKey.isEmpty || !openaiKey.isEmpty || !sonioxKey.isEmpty
        guard hasAnyStt && !geminiKey.isEmpty else {
            showError = true
            return
        }

        appViewModel.saveKeys(
            speech: speechKey.trimmingCharacters(in: .whitespacesAndNewlines),
            openai: openaiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            soniox: sonioxKey.trimmingCharacters(in: .whitespacesAndNewlines),
            gemini: geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Clear fields
        speechKey = ""
        openaiKey = ""
        sonioxKey = ""
        geminiKey = ""
    }
}
