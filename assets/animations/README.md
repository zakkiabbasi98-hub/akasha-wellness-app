# Animations

Every animation in AKASHA is drawn in Flutter (CustomPainter + AnimationController)
rather than shipped as a Lottie/Rive file, so:

* the app works entirely offline with no extra engine,
* the water droplet and breathing circle scale perfectly on every screen size,
* there is nothing to load on first launch.

See `lib/shared/widgets/water_drop.dart` (droplet + droplet meter) and
`lib/shared/widgets/progress_ring.dart` (progress ring + water fill).

If you later add a Lottie/Rive asset, place it here and register the package;
the directory is already declared in `pubspec.yaml`.
