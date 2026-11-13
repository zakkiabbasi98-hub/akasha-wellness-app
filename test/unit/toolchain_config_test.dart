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

  group('Dart dependency constraints', () {
    /// Every `name: constraint` pair in the two dependency sections.
    Map<String, String> constraints() {
      final out = <String, String>{};
      var section = '';
      for (final raw in read('pubspec.yaml').split('\n')) {
        if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
        if (!raw.startsWith(' ')) {
          section = raw.split(':').first.trim();
          continue;
        }
        if (section != 'dependencies' && section != 'dev_dependencies') {
          continue;
        }
        final m = RegExp(r'^  ([a-z_0-9]+):\s*(.+?)\s*$').firstMatch(raw);
        if (m == null) continue;
        // Drop a trailing comment before inspecting the value.
        final value = m.group(2)!.split(RegExp(r'\s+#')).first.trim();
        out[m.group(1)!] = value;
      }
      return out;
    }

    test('the dependency sections are actually found', () {
      final all = constraints();
      expect(all, isNotEmpty);
      expect(all.keys, containsAll(<String>[
        'flutter_local_notifications',
        'timezone',
        'share_plus',
        'sqflite',
        'sqflite_common_ffi',
      ]));
    });

    test('every constraint uses valid pub syntax', () {
      // Pub accepts `^x.y.z`, ranges (`>=x <y`) and bare versions. Everything
      // here must be one of those; anything else is the invalid-syntax class of
      // bug this pass exists to remove.
      final caret = RegExp(r'^\^\d+\.\d+\.\d+([-+][0-9A-Za-z.+-]+)?$');
      final exact = RegExp(r'^\d+\.\d+\.\d+([-+][0-9A-Za-z.+-]+)?$');
      final range = RegExp(r'^[<>]=?\d+\.\d+\.\d+\s+[<>]=?\d+\.\d+\.\d+$');
      final sdkEntry = RegExp(r'^sdk:');
      final offenders = <String>[];
      constraints().forEach((name, value) {
        if (sdkEntry.hasMatch(value)) return; // `sdk: flutter`
        final v = value.replaceAll('"', '').replaceAll("'", '');
        if (caret.hasMatch(v) || exact.hasMatch(v) || range.hasMatch(v)) return;
        offenders.add('$name: $value');
      });
      expect(offenders, isEmpty,
          reason: 'Unrecognised version syntax: ${offenders.join(', ')}');
    });

    test('no tilde constraint exists anywhere in pubspec.yaml', () {
      // Explicit project rule: `~` is never used for a version constraint.
      for (final line in read('pubspec.yaml').split('\n')) {
        if (RegExp(r'^\s+[a-z_0-9]+:\s+~').hasMatch(line)) {
          fail('Tilde constraint found: ${line.trim()}');
        }
      }
    });

    test('flutter_local_notifications stays on the 17.x API surface', () {
      // `^17.2.4` means >=17.2.4 <18.0.0 — it cannot reach 18/19, where
      // uiLocalNotificationDateInterpretation and the positional
      // zonedSchedule the code is written against disappear.
      expect(constraints()['flutter_local_notifications'], '^17.2.4');
    });

    test('timezone is the range 17.2.4 requires', () {
      // A 0.x caret stops at the next minor, so ^0.9.4 is >=0.9.4 <0.10.0.
      expect(constraints()['timezone'], '^0.9.4');
    });

    test('share_plus stays inside the 12.x line', () {
      // 10/11 pin Kotlin 1.7.22 + AGP 8.3.1; 13 drops the JVM-target guard.
      expect(constraints()['share_plus'], '^12.0.2');
    });

    test('there is no dependency_overrides section', () {
      // Overrides silently defeat the constraints above.
      expect(read('pubspec.yaml'), isNot(contains('dependency_overrides')));
    });
  });
}
