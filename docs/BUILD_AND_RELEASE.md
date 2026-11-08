# AKASHA — Build & release

Everything below has been written to match the Gradle files in this repository.
**No build was executed while authoring this project** (the authoring environment
had no Flutter/Android SDK), so treat these as precise, first-principles
instructions rather than a log of a successful build. If a step fails, the failure
will be in your toolchain, not in a missing file — every file the Android build
needs is present.

---

## 1. Toolchain

| Component | Required | Why |
|---|---|---|
| Flutter | stable **≥ 3.27** | `WidgetStateProperty`, `Color.withValues`, `CardThemeData`, `TextScaler.clamp` |
| Dart | ≥ 3.6 | pinned in `pubspec.yaml` (`sdk: ">=3.6.0 <4.0.0"`) |
| JDK | **17** | AGP 8.1 + `coreLibraryDesugaring` |
| Gradle | 8.3 (wrapper) | AGP 8.1.0 requires ≥ 8.0 |
| AGP | 8.1.0 | declared in `android/settings.gradle` |
| Kotlin | 1.9.10 | declared in `android/settings.gradle` |
| Android SDK Platform | **34** | `compileSdk = 34` |
| Build Tools | 34.0.0 | |
| minSdk | 23 (Android 6.0) | |
| targetSdk | 34 (Android 14) | |

Check it:

```bash
flutter --version
flutter doctor -v
java -version        # expect 17.x
```

If `java -version` is not 17: Android Studio → *Settings → Build, Execution,
Deployment → Build Tools → Gradle → Gradle JDK* → select the bundled **jbr-17**.

---

## 2. First run in Android Studio

1. *File → Open* → choose the folder containing `pubspec.yaml`.
2. Let the IDE index, then in the terminal:
   ```bash
   flutter pub get
   ```
3. If prompted about the Android SDK location:
   ```bash
   flutter config --android-sdk ~/Android/Sdk     # adjust to your path
   ```
4. Accept licences (once per machine):
   ```bash
   flutter doctor --android-licenses
   ```
5. Pick a device:
   ```bash
   flutter devices
   ```
6. Run:
   ```bash
   flutter run
   ```
   Or press ▶ in Android Studio.

First build downloads Gradle + AGP + Kotlin + all plugin AARs: expect 3–10 minutes
and ~500 MB of caches. Subsequent builds are ~30 s.

---

## 3. Debug build

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

* Signed with the local debug keystore, installable on any device.
* Includes the Dart VM service — slower and larger than release. Use it for
  development, not for daily use.
* Install:
  ```bash
  adb install -r build/app/outputs/flutter-apk/app-debug.apk
  ```

Alternative while iterating (fastest on a physical device):
```bash
flutter run --release   # no VM overhead, profile-like performance
flutter run --profile   # measure UI jank in DevTools
```

---

## 4. Release build

### 4.1 Without a keystore (installs immediately)

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

If `android/key.properties` does not exist, `android/app/build.gradle` falls back to
the **debug signing config**. That is deliberate: it means a fresh clone can produce
an installable release APK without you having to create a keystore first. It is
**not** suitable for the Play Store (and Play will reject an APK signed by a debug
key).

### 4.2 With your own keystore (Play Store ready)

1. Create the keystore (keep it safe; losing it means you can never update the app):

   ```bash
   keytool -genkey -v \
     -keystore ~/akasha-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias akasha
   ```
   Remember the store password / key password. If you do, recover with
   `keytool -list -keystore ~/akasha-release.jks`.

2. Create `android/key.properties` (**never committed** — it is in `.gitignore`):

   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=akasha
   storeFile=/absolute/path/to/akasha-release.jks
   ```

3. Build:

   ```bash
   flutter build apk --release
   flutter build appbundle --release
   ```

   Outputs:
   * `build/app/outputs/flutter-apk/app-release.apk`
   * `build/app/outputs/bundle/release/app-release.aab`

4. Verify the signature:

   ```bash
   apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
   ```

### 4.3 Split APKs (smaller download per device ABI)

```bash
flutter build apk --release --split-per-abi
```
Outputs `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`,
`app-x86_64-release.apk`. Use the arm64 one for any phone from ~2017 onward.

### 4.4 With the optional AI endpoint

```bash
flutter build apk --release \
  --dart-define=AKASHA_AI_ENDPOINT=https://us-central1-<project>.cloudfunctions.net/akashaCompanion
```

`--dart-define` values are compiled in; they are **not** secrets (the endpoint is
public), and no provider API key is ever passed this way.

---

## 5. Versioning

`pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^     ^
#        |     versionCode (must increase for every Play upload)
#        versionName (what she sees)
```

`android/app/build.gradle` reads these through `local.properties`
(`flutter.versionCode` / `flutter.versionName`), which Flutter writes on every
build — no manual duplication.

---

## 6. Play Store checklist

1. **App bundle**, not APK: `flutter build appbundle --release`.
2. **Signing:** upload key registered with Play App Signing. Keep the keystore and
   its passwords somewhere you will not lose them.
3. **Data safety form** — answer truthfully against `docs/PRIVACY.md`:
   * Data collected: **none** by default.
   * Data shared: **none** (AI messages only if the user enables the companion and
     you run the function).
   * Optional collection: email address, only if the user turns on cloud sync.
   * Encrypted in transit: yes (TLS to Firestore / the function).
   * Users can request deletion: yes — in-app (Settings → Privacy / Profile).
4. **Health apps declaration:** AKASHA is a *wellness/reminder* app, not a medical
   device. Do not select the medical-device category; do state that it does not
   diagnose or treat. The medication feature is a reminder list, not dosage advice.
5. **Permissions declaration:** `USE_FULL_SCREEN_INTENT` may
   require a short justification form on recent Android versions. Explain: alarm
   clock-style reminder app; the user can revoke both, and the app degrades
   gracefully (it never claims otherwise).
6. **Notification permission** is requested at runtime with an explanation — never
   on first frame.
7. **Store listing assets** (not in this repo): 512×512 icon, 1024×500 feature
   graphic, at least 2 phone screenshots. Generate screenshots from a real build.
8. **Privacy policy URL** — host `docs/PRIVACY.md` somewhere public; Play requires a
   reachable URL even for apps that collect nothing.

---

## 7. Expected build output sizes

| Artifact | Approximate size |
|---|---|
| `app-debug.apk` | 55–75 MB (all ABIs, no shrinking) |
| `app-release.apk` (all ABIs) | 20–28 MB |
| `app-release.apk` (arm64 only) | 9–13 MB |
| `app-release.aab` | 18–25 MB |

The `fl_chart`, Firebase and `local_auth` plugins are the bulk. If you disable
Firebase (see step 4.5 below), the release APK drops by roughly 3–5 MB.

---

## 8. Build troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Unsupported class file major version 6x` | Gradle running on JDK 21+ | Set Gradle JDK to 17 |
| `Requires Android SDK 34` | Platform not installed | SDK Manager → install Android 14 (API 34) |
| `minSdkVersion 21 cannot be smaller than 23` | a plugin wants 23 | already 23; if you edited it, restore |
| `Duplicate class ... kotlin-stdlib` | stale caches | `flutter clean && rm -rf ~/.gradle/caches/transforms-*` then rebuild |
| `Execution failed for task ':app:checkDebugDuplicateClasses'` | conflicting plugin versions | `flutter pub deps --style=compact` and check for a second copy of a plugin |
| `File google-services.json is missing` | the plugin is enabled without config | add the file, or re-comment the plugin lines |
| `Could not resolve com.google.gms:google-services` | no `google()` repo access | check the proxy / network; or keep Firebase disabled |
| Desugaring error on `java.time` | `coreLibraryDesugaring` missing | it is configured; do not remove it |
| `Gradle build daemon disappeared` | memory | add `org.gradle.jvmargs=-Xmx3g` to `android/gradle.properties` |
| Notifications never appear on a real device | battery optimisation / permission | Settings → Diagnostics inside the app |
| White screen on launch on a very old device | unsupported Android version | minSdk is 23; below that, install fails cleanly |

### Disabling Firebase entirely

If you will never use sync, you can strip ~4 MB and the whole Google Play Services
dependency:

1. Keep the `google-services` plugin lines commented (they already are).
2. Optionally comment out `firebase_core`, `firebase_auth`, `cloud_firestore`,
   `firebase_messaging` in `pubspec.yaml`.
3. Delete `lib/features/sync/firebase_backend.dart` and remove its import plus
   `_tryFirebase()` from `lib/main.dart`.

The app is designed so that this leaves a fully functional product: the
`CloudBackend` interface and `LocalOnlyBackend` remain, and Cloud backup simply
reports "not configured on this build".

---

## 9. Reproducibility notes

* `pubspec.yaml` uses caret ranges so patch fixes flow in; the resolved set is
  pinned at build time by `pubspec.lock` (**commit it** — it is not ignored).
* Gradle dependency versions are pinned in `android/settings.gradle` and
  `android/app/build.gradle`; the wrapper version lives in
  `android/gradle/wrapper/gradle-wrapper.properties`.
* No code generation step (`build_runner`) exists, so a build cannot fail because
  generated files are stale.
* `assets/` contains only the logo mark and documentation; fonts and sounds are
  opt-in (see `assets/fonts/README.md`, `assets/sounds/README.md`).
