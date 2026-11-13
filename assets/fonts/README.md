# Optional custom typography

AKASHA ships with **zero bundled fonts** on purpose: it keeps the APK small,
works fully offline, and avoids a network fetch on first launch. The theme uses
the platform font (Roboto on Android) with carefully tuned weights, sizes and
letter-spacing — see `lib/core/theme/app_theme.dart`.

## Adding Poppins (or any other face)

1. Download the font files (e.g. from Google Fonts) and drop them here:

       assets/fonts/Poppins-Regular.ttf
       assets/fonts/Poppins-Medium.ttf
       assets/fonts/Poppins-SemiBold.ttf
       assets/fonts/Poppins-Bold.ttf

2. In `pubspec.yaml`, uncomment the `fonts:` block (it is already written for
   you) and confirm `assets/fonts/` is not ignored.

3. In `lib/core/theme/app_theme.dart`, set:

       static const String? fontFamily = 'Poppins';

4. Re-run the app. Nothing else needs to change: every text style inherits from
   `AppTheme._textTheme`.

## Licence

Fonts carry their own licences (Poppins and most Google Fonts are OFL 1.1).
Add the licence file next to the fonts before publishing a public build.
