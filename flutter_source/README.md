# Listen with Eve

Cross-platform Flutter app that lets you talk to Grok (xAI) in **English** or **Afrikaans**, with full voice input + voice replies and the ability to select default voices or teach/clone a custom voice.

**App name: Listen with Eve**

## Features

- Real-time voice conversations powered by xAI Grok Voice API
- Text chat fallback
- Language switching (English / Afrikaans)
- Default Grok voices (Eve, Ara, Leo, Rex, Sal + others)
- Custom voice cloning (record a sample and create a new voice)
- Clean, modern UI with dark mode support
- Chat history persisted locally

## Requirements

- Flutter 3.22+ / Dart 3.2+
- xAI API key from https://console.x.ai
- Android Studio / VS Code + Flutter extension
- For iOS: Xcode + CocoaPods

## Setup

1. Create a new Flutter project (or clone this folder structure):
   ```bash
   flutter create listen_with_eve
   cd listen_with_eve
   ```

2. Replace the generated files with the ones in this repository (especially `lib/` and `pubspec.yaml`).

3. Install dependencies:
   ```bash
   flutter pub get
   ```

4. Add your xAI API key:
   - Open `lib/services/xai_service.dart`
   - Or better: use a `.env` file / secure storage (recommended for production)
   - For quick testing you can temporarily hard-code it (never commit real keys)

5. Run:
   ```bash
   flutter run
   ```

## Important Notes

- **Custom Voices** are currently limited geographically (mainly United States). The app includes the UI and API calls; if your region is restricted the feature will show an appropriate message.
- **Afrikaans** support uses language hints + system instructions. Quality is good but not yet at the same level as English.
- For production you should:
  - Use **ephemeral tokens** (never put the long-lived API key in the mobile app)
  - Add a small backend that issues short-lived client secrets
  - Handle microphone permissions carefully

## Project Structure

```
lib/
  main.dart                 # Entry point
  models/                   # Data models
  providers/                # State management
  screens/                  # UI screens
  services/                 # xAI API, audio, storage
  widgets/                  # Reusable widgets
```

## Next Steps After First Run

1. Test text chat
2. Grant microphone permission and test voice
3. Try switching language
4. Explore voice selection in Settings
5. (Optional) Record a custom voice sample

Enjoy talking to Grok!
