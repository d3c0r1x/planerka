# Android release signing

Release APKs use a private signing key. Keep the keystore and its properties file
local and never commit either file. Android updates must keep the same signing key.

## Local setup

Create these ignored local files:

- `android/key.properties`
- `android/app/ritm-dnya-release.keystore`

The properties file contains these fields:

```properties
storeFile=ritm-dnya-release.keystore
storePassword=<private password>
keyAlias=<private alias>
keyPassword=<private password>
```

Keep a secure backup of the keystore. Gradle stops release tasks when the
properties file is missing; debug builds do not need signing material.

## Build and verify

```powershell
flutter build apk --release --target-platform android-arm64
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Before sharing an APK, confirm its package, ABI, min SDK, signature, SHA-256,
permissions, and contents. The local model and personal seed must not be in the
APK.
