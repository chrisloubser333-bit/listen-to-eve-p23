# Listen to Eve

Listen to Eve is a Flutter mobile AI companion focused on natural conversation, distinct characters, persistent memory, voice interaction, image generation, and provider-independent intelligence.

The current characters are Eve, Ara, Leo, Rex, and Sal. Each character can have its own identity, voice, conversation context, and memory.

## Current architecture

- Flutter mobile application for Android and iOS
- Provider abstraction with Gemini and xAI implementations
- Switchable AI provider architecture
- Persistent local conversation and memory services
- Intelligence orchestration with tool support
- Weather and web-search tools through backend/proxy transports
- Image generation through a backend image proxy
- Speech input, text-to-speech, neural voice generation, and local voice caching
- Character-specific profiles and selectable voices
- Local image persistence and image viewing/sharing UI
- English and Afrikaans conversation support

## Project structure

```text
android/             Android application and Gradle configuration
ios/                 iOS application configuration
assets/              Character and avatar artwork
lib/
  models/            Domain and conversation models
  providers/         Application state and chat/settings providers
  screens/           Main application screens
  services/          AI, memory, voice, storage, tools, and transports
  theme/             Application theme
  widgets/           Reusable UI components
test/                Flutter tests
pubspec.yaml         Flutter package configuration
```

## Development setup

Requirements:

- Flutter stable
- Dart supplied by Flutter
- Android SDK for Android builds
- Xcode and CocoaPods for iOS builds

Install dependencies and verify the project:

```bash
flutter pub get
flutter analyze
flutter test
```

Build an Android release APK with:

```bash
flutter build apk --release
```

## Configuration

Do not commit API keys, signing credentials, `.env` files, or machine-specific configuration.

The application can obtain backend endpoints from saved settings or Dart environment values such as:

- `SERVER_BASE_URL`
- `SEARCH_PROXY_ENDPOINT`
- `IMAGE_PROXY_ENDPOINT`

Provider credentials are managed separately by the application. Production deployments should keep long-lived provider credentials on trusted backend infrastructure wherever possible rather than embedding them in the mobile application.

## Repository workflow

`main` is the stable source of truth. Substantial work should be performed on a dedicated feature or fix branch, verified with analysis/tests/builds as appropriate, reviewed, and then merged into `main`.

Generated Flutter output, local Android configuration, signing credentials, IDE files, logs, and temporary files are intentionally excluded by `.gitignore`.

## Release note

The current Android configuration is suitable for development builds. Before public/store release, configure a permanent application ID/package namespace and production signing credentials.
