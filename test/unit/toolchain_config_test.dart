import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the pieces of the Android/toolchain configuration that are easy to
/// regress and impossible to notice until a real `flutter build apk` fails on a
/// machine that has the SDK. Reading the files is the only way to check them
/// from a test, and each assertion below corresponds to a real build failure
/// observed in the project's build log.
void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  group('Gradle toolchain consistency', () {
    test('AGP is pinned below 9 and matches the wrapper', () {
      final settings = read('android/settings.gradle');
      final agp =
          RegExp(r'id "com\.android\.application" version "([\d.]+)"')
              .firstMatch(settings)!
              .group(1)!;
      expect(agp, '8.11.1');

      final major = int.parse(agp.split('.').first);
      expect(major, lessThan(9),
          reason: 'AGP 9 forces Built-in Kotlin and breaks the plugin graph.');
    });

    test('Gradle wrapper matches what AGP 8.11.1 requires', () {
      final props = read('android/gradle/wrapper/gradle-wrapper.properties');
      expect(props, contains('gradle-8.14-bin.zip'));
    });

    test('Kotlin is the version AGP 8.11 expects', () {
      final settings = read('android/settings.gradle');
      expect(settings, contains('id "org.jetbrains.kotlin.android" version "2.2.20"'));
    });

    test('the wrapper JAR is present and is a real JAR', () {
      // Toolchain upgrades have twice replaced this file; a truncated or
      // placeholder JAR makes `flutter build` fail with an opaque
      // "Could not find or load main class GradleWrapperMain".
      final jar = File('android/gradle/wrapper/gradle-wrapper.jar');
      expect(jar.existsSync(), isTrue);
      final header = jar.readAsBytesSync().sublist(0, 2);
      // A JAR is a ZIP: every valid archive starts with "PK".
      expect(String.fromCharCodes(header), 'PK');
      expect(jar.lengthSync(), greaterThan(20000));
    });

    test('the wrapper script is executable shell, not a placeholder', () {
      final script = read('android/gradlew');
      expect(script, contains('GradleWrapperMain'));
    });
  });

  group('Android SDK levels', () {
    test('compileSdk and targetSdk are 36', () {
      final gradle = read('android/app/build.gradle');
      expect(gradle, contains('compileSdk = 36'));
      expect(gradle, contains('targetSdk = 36'));
    });

    test('core library desugaring is on and recent enough for SDK 36', () {
      final gradle = read('android/app/build.gradle');
      expect(gradle, contains('coreLibraryDesugaringEnabled = true'));
      // 2.0.4 fails against the AndroidX versions compileSdk 36 resolves.
      expect(gradle, contains('desugar_jdk_libs:2.1.5'));
      expect(gradle, isNot(contains('desugar_jdk_libs:2.0.4')));
    });

    test('bytecode target stays on Java 17 while building with JDK 21', () {
      final gradle = read('android/app/build.gradle');
      expect(gradle, contains('sourceCompatibility = JavaVersion.VERSION_17'));
      expect(gradle, contains('JvmTarget.JVM_17'));
    });

    test('the removed `kotlinOptions` DSL is not used anywhere', () {
      // Kotlin 2.2 raises `kotlinOptions {}` from warning to error
      // ("Using 'kotlinOptions: KotlinJvmOptions' is an error. Please migrate
      // to the compilerOptions DSL."). It must be gone from the app module.
      final gradle = read('android/app/build.gradle');
      expect(gradle, isNot(contains('kotlinOptions {')),
          reason: 'Kotlin 2.2 refuses the kotlinOptions DSL.');
      expect(gradle, contains('kotlin {'));
      expect(gradle, contains('compilerOptions {'));
    });

    test('minSdk is unchanged at 23', () {
      expect(read('android/app/build.gradle'), contains('minSdk = 23'));
    });
  });

  group('notification permissions in the manifest', () {
    test('scheduled exact alarms use SCHEDULE_EXACT_ALARM, not USE_EXACT_ALARM',
        () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('SCHEDULE_EXACT_ALARM'));
      // Play restricts USE_EXACT_ALARM to alarm-clock apps.
      expect(manifest, isNot(contains('android.permission.USE_EXACT_ALARM')));
    });

    test('POST_NOTIFICATIONS and boot rescheduling are declared', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('POST_NOTIFICATIONS'));
      expect(manifest, contains('RECEIVE_BOOT_COMPLETED'));
      expect(manifest, contains('USE_FULL_SCREEN_INTENT'));
    });
  });

  group('Kotlin bridge matches the Dart channel', () {
    test('MainActivity answers the methods SystemChannel sends', () {
      final kotlin =
          read('android/app/src/main/kotlin/com/akasha/wellness/MainActivity.kt');
      for (final method in [
        'canScheduleExactAlarms',
        'isIgnoringBatteryOptimizations',
        'isNotificationPolicyAccessGranted',
        'isDndActive',
        'consumeRescheduleRequest',
        'canUseFullScreenIntent',
        'openFullScreenIntentSettings',
        'deviceSdkInt',
      ]) {
        expect(kotlin, contains('"$method"'),
            reason: 'Dart invokes "$method"; the Kotlin side must answer it.');
      }
    });

    test('the channel name is identical on both sides', () {
      final kotlin =
          read('android/app/src/main/kotlin/com/akasha/wellness/MainActivity.kt');
      expect(kotlin, contains('com.akasha.wellness/system'));
    });

    test('the full-screen check is version-guarded to Android 14+', () {
      final kotlin =
          read('android/app/src/main/kotlin/com/akasha/wellness/MainActivity.kt');
      expect(kotlin, contains('canUseFullScreenIntent()'));
      expect(kotlin, contains('Build.VERSION.SDK_INT >= 34'),
          reason: 'The API does not exist before API 34 and would crash.');
    });
  });

  group('Dart dependency pins', () {
    test('flutter_local_notifications stays on the 17.x API surface', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('flutter_local_notifications: ~17.2.4'));
      // 18+ removes uiLocalNotificationDateInterpretation entirely.
      expect(pubspec, isNot(contains('flutter_local_notifications: ^19')));
    });

    test('timezone matches what 17.2.4 requires', () {
      expect(read('pubspec.yaml'), contains('timezone: ~0.9.4'));
    });

    test('share_plus is pinned where the Kotlin plugin still builds', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('share_plus: ~12.0.2'));
    });
  });
}
