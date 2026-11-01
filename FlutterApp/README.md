# StudyGo Flutter client

This directory contains the initial Flutter Android/iOS client connected to the StudyGo PHP API.

## Prepare platform folders
The repository keeps app source and dependencies only. Generate native Android/iOS runner folders once:
\`\`\`bash
cd FlutterApp
flutter create --platforms=android,ios --project-name studygo_app .
flutter pub get
\`\`\`
Keep the existing \`lib/\` sources and verify dependencies from this \`pubspec.yaml\` after generation.

## Run
\`\`\`bash
flutter run --dart-define=STUDYGO_API_URL=https://YOUR_API_HOST
\`\`\`

## Build APK
\`\`\`bash
flutter build apk --release --dart-define=STUDYGO_API_URL=https://YOUR_API_HOST
\`\`\`

The client stores opaque access/refresh tokens using flutter_secure_storage and rotates sessions on 401. Do not hardcode API provider keys in this app. The server is authoritative for identity, quota, rewards and file access.

Current screens: login, AI text tutor, image question recognition, planner task list, material upload, notification list. The app is a starter integration, not a finished product UI. Verify login and all API calls against a deployed staging API before release.
