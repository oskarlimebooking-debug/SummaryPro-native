# Summary Pro - Native iOS App

A native iOS app for AI-powered meeting summaries. Record audio, transcribe it using multiple speech-to-text providers, and summarize it with Google Gemini AI.

**BYOK (Bring Your Own Keys)** - All API keys are stored securely in your device's Keychain. No server-side processing.

## Features

- **Audio Recording** with real-time frequency visualizer
- **Three STT Providers**: Google Speech-to-Text, OpenAI Whisper, Soniox
- **AI Summarization** via Google Gemini (dynamic model selection)
- **9 Languages**: Slovenian, English (US/UK), German, Croatian, Serbian, Italian, French, Spanish
- **Recording History** with full transcript and summary storage (max 50 entries)
- **Summary Regeneration** with different AI models
- **Background Recording** support (continues when app is backgrounded)
- **Crash Recovery** for interrupted recordings
- **Copy to Clipboard** for transcripts and summaries
- **Zero External Dependencies** - Pure SwiftUI + native iOS frameworks

## Requirements

- **iOS 16.0+** (iPhone and iPad)
- **Xcode 15.0+** (for building)
- At least one STT API key (Google Cloud, OpenAI, or Soniox)
- A Google Gemini API key

---

## Building the App

### Option A: Building on a Mac (Recommended)

#### Prerequisites

1. **Xcode 15.0+** - Download from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835)
2. **Apple ID** - Free Apple ID is sufficient for development builds
3. **Apple Developer Program** ($99/year) - Only needed for TestFlight/App Store distribution

#### Steps

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd Summary-pro/SummaryPro
   ```

2. **Open in Xcode:**
   ```bash
   open SummaryPro.xcodeproj
   ```

3. **Configure Signing:**
   - In Xcode, select the `SummaryPro` target
   - Go to **Signing & Capabilities** tab
   - Select your **Team** (your Apple ID)
   - Xcode will automatically manage signing

4. **Select your device:**
   - Connect your iPhone/iPad via USB
   - Select it from the device dropdown in Xcode's toolbar
   - Or select a Simulator (e.g., "iPhone 15")

5. **Build and Run:**
   - Press `Cmd + R` or click the Play button
   - First time: You may need to trust the developer certificate on your device
     - On your iPhone: **Settings > General > VPN & Device Management > [Your Apple ID] > Trust**

#### Building from Command Line

```bash
cd Summary-pro/SummaryPro

# Build for simulator
xcodebuild -project SummaryPro.xcodeproj \
  -scheme SummaryPro \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# Build for device (requires signing)
xcodebuild -project SummaryPro.xcodeproj \
  -scheme SummaryPro \
  -sdk iphoneos \
  -configuration Release \
  -allowProvisioningUpdates \
  build
```

---

### Option B: Building WITHOUT a Mac (Cloud Build)

If you don't have a Mac, you can use cloud-based build services.

#### GitHub Actions (Free for public repos)

This repository includes a GitHub Actions workflow that builds the app automatically.

1. **Fork this repository** on GitHub

2. **Enable GitHub Actions** in your fork (Settings > Actions > Allow all actions)

3. **Push a commit** or manually trigger the workflow:
   - Go to **Actions** tab > **Build iOS App** > **Run workflow**

4. **Download the build artifact:**
   - After the workflow completes, go to the workflow run
   - Download the `SummaryPro-build` artifact (contains the `.app` bundle)

5. **Install on device** - See "Installing on a Device" section below

> **Note:** GitHub Actions builds are unsigned by default. To create a signed `.ipa` for real device installation, you'll need to add your Apple certificates as GitHub Secrets. See the workflow file for details.

#### Codemagic (Alternative)

1. Sign up at [codemagic.io](https://codemagic.io)
2. Connect your GitHub repository
3. Add a new iOS application
4. Configure:
   - **Xcode version**: 15.0+
   - **Build scheme**: SummaryPro
   - **Project path**: `SummaryPro/SummaryPro.xcodeproj`
5. (Optional) Add Apple certificates for signing
6. Start a build

#### MacInCloud / MacStadium (Remote Mac)

If you need full Xcode access without owning a Mac:
- [MacInCloud](https://www.macincloud.com) - Pay-per-use remote Mac ($1-3/hour)
- [MacStadium](https://www.macstadium.com) - Dedicated Mac servers (monthly plans)

---

## Installing on a Device

### Method 1: Direct from Xcode (Requires Mac)

1. Connect your iPhone/iPad via USB
2. Open the project in Xcode
3. Select your device from the toolbar
4. Press `Cmd + R`
5. Trust the developer certificate on your device if prompted

### Method 2: TestFlight (Requires Apple Developer Program - $99/year)

1. In Xcode: **Product > Archive**
2. In the Organizer: **Distribute App > TestFlight**
3. Upload to App Store Connect
4. Add testers in [App Store Connect](https://appstoreconnect.apple.com)
5. Testers install via the TestFlight app

### Method 3: AltStore (Free, works from Windows/Mac)

[AltStore](https://altstore.io) lets you sideload apps using a free Apple ID.

1. **Install AltServer** on your computer (Windows or Mac)
2. **Install AltStore** on your iPhone via AltServer
3. **Export the .ipa** from Xcode:
   - Product > Archive
   - Distribute App > Custom > Ad Hoc > Export
4. **Send the .ipa** to your iPhone (AirDrop, email, or cloud storage)
5. **Open with AltStore** to install

> **Limitation:** Free Apple IDs can only sign apps for 7 days. You'll need to re-sign weekly using AltStore.

### Method 4: Sideloadly (Free, Windows/Mac)

[Sideloadly](https://sideloadly.io) is another sideloading tool.

1. Download and install Sideloadly
2. Connect your iPhone via USB
3. Drag the `.ipa` file into Sideloadly
4. Enter your Apple ID
5. Click "Start"

> **Same 7-day limitation** as AltStore for free Apple IDs.

---

## Getting API Keys

### Google Cloud Speech-to-Text

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project (or select existing)
3. Enable the **Cloud Speech-to-Text API**
4. Go to **APIs & Services > Credentials**
5. Create an **API Key**
6. (Recommended) Restrict the key to Speech-to-Text API only

### OpenAI (for Whisper STT)

1. Go to [platform.openai.com](https://platform.openai.com)
2. Sign up or log in
3. Go to **API Keys**
4. Create a new secret key

### Soniox

1. Go to [soniox.com](https://soniox.com)
2. Sign up for an account
3. Navigate to API settings
4. Copy your API key

### Google Gemini

1. Go to [aistudio.google.com](https://aistudio.google.com)
2. Click **Get API Key**
3. Create a new API key or use existing one

---

## Project Structure

```
SummaryPro/
├── SummaryPro.xcodeproj/         # Xcode project file
├── SummaryPro/
│   ├── SummaryProApp.swift        # App entry point
│   ├── Info.plist                 # Permissions & configuration
│   ├── Assets.xcassets/           # App icons & colors
│   │
│   ├── Models/
│   │   ├── STTProvider.swift      # STT provider enum + languages
│   │   ├── GeminiModel.swift      # AI model definition
│   │   └── RecordingEntry.swift   # History entry model
│   │
│   ├── Services/
│   │   ├── AudioRecorder.swift    # AVAudioEngine recording
│   │   ├── GoogleSpeechService.swift
│   │   ├── WhisperService.swift
│   │   ├── SonioxService.swift
│   │   ├── GeminiService.swift
│   │   ├── KeychainService.swift  # Secure API key storage
│   │   └── HistoryStore.swift     # UserDefaults persistence
│   │
│   ├── ViewModels/
│   │   ├── AppViewModel.swift     # App state & settings
│   │   ├── RecordingViewModel.swift
│   │   └── HistoryViewModel.swift
│   │
│   └── Views/
│       ├── ContentView.swift      # Main tab view
│       ├── SetupView.swift        # API key entry
│       ├── RecordingView.swift    # Recording screen
│       ├── AudioVisualizerView.swift
│       ├── ProcessingView.swift   # Progress display
│       ├── ResultsView.swift      # Transcript + summaries
│       ├── HistoryListView.swift
│       ├── HistoryDetailView.swift
│       └── SummaryCardView.swift
└── README.md
```

## Troubleshooting

### "Untrusted Developer" error on device

Go to **Settings > General > VPN & Device Management** on your iPhone, find your developer certificate, and tap **Trust**.

### Microphone permission denied

The app requests microphone access on first recording. If you denied it:
- Go to **Settings > Privacy & Security > Microphone > Summary Pro** and enable it.

### Build fails with signing errors

- Make sure you've selected a valid team in Xcode's Signing & Capabilities
- For free Apple IDs: You can only have 3 apps installed at once
- Try: **Xcode > Settings > Accounts > Download Manual Profiles**

### "No such module" errors

Clean the build folder: **Product > Clean Build Folder** (`Cmd + Shift + K`)

### API key not working

- Check that the API key is correct (no extra spaces)
- Google Speech: Make sure the Speech-to-Text API is enabled in your Google Cloud project
- OpenAI: Make sure you have billing set up and credits available
- Check your network connection (the app requires internet for API calls)

### Recording stops in background

The app is configured for background audio, but iOS may still suspend it in low-memory situations. Keep the app in the foreground for best results.

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI (iOS 16+) |
| Audio Recording | AVAudioEngine + AVAudioSession |
| Audio Visualization | SwiftUI Canvas |
| Networking | URLSession + async/await |
| API Key Storage | iOS Keychain (Security framework) |
| History Storage | UserDefaults (JSON-encoded) |
| Background Audio | AVAudioSession background mode |
| Dependencies | None (zero external packages) |

---

## License

See the main repository LICENSE file.
