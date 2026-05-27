# Coloring Game

A multiplayer coloring by numbers game built with Flutter and Firebase, featuring real-time collaborative coloring and voice chat powered by Agora!

## Features
- **Color by Numbers**: Detailed pixel grids. Zoom and pan using two fingers, paint using one finger.
- **Multiplayer Mode**: Collaborate with other users in real-time.
- **Voice Chat**: Talk to your friends while painting together.
- **Progress Tracking**: See total brush strokes and each player's contribution.

## Setup Instructions

This project uses some third-party services that require API keys. The keys are intentionally excluded from the repository. Follow these steps to set up the project locally:

### 1. Firebase Configuration
You need to connect this app to your own Firebase project for the real-time database to work.
- Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project.
- Enable **Realtime Database**.
- Add an Android app and download the `google-services.json` file. Place it in `android/app/google-services.json`.
- Add an iOS app and download the `GoogleService-Info.plist` file. Place it in `ios/Runner/GoogleService-Info.plist`.
- You can also run `flutterfire configure` to automatically generate `lib/firebase_options.dart`.

### 2. Agora Voice Chat Configuration
For voice chat to work, you need an Agora App ID.
- Go to the [Agora Console](https://console.agora.io/) and create a new project.
- **IMPORTANT**: Make sure to select **Testing Mode (App ID only / No Certificate)** when creating the project.
- Copy your App ID.
- Copy the example config file:
  ```bash
  cp lib/config/app_config.example.dart lib/config/app_config.dart
  ```
- Open `lib/config/app_config.dart` and paste your App ID.

### 3. Run the App
Once the configuration is complete, run the following commands:
```bash
flutter pub get
flutter run
```

## Disclaimer
The original `app_config.dart`, `google-services.json`, and `firebase_options.dart` files contain sensitive keys and are listed in `.gitignore`. Do not commit these files to public repositories.
