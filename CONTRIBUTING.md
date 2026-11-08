# Contributing to AKASHA

Thank you for wanting to make this gentler. This project has one non-negotiable
value system, and everything else is negotiable.

## The three rules

1. **Never shame.** No copy that implies failure. No red "you missed it" banners.
   No streak-guilt. No exclamation marks in error states. Read the existing tone
   in `lib/content/motivation_content.dart` before writing any new string.
2. **Never lie to the user.** No fake data, no sample numbers shown as real
   history, no percentages without a denominator, no "synced" badge when nothing
   was synced. If a feature needs a permission it does not have, the UI must say
   so plainly.
3. **Never diagnose.** No medical interpretation, no dosage advice, no "you
   should drink more because…" reasoning. Reminders are memory aids.

If a change breaks any of the three, it is not merged — regardless of how nice it
looks.

## Getting set up

```bash
git clone <your-fork>
cd akasha-wellness-app
flutter --version          # need stable >= 3.27 / Dart >= 3.6
flutter pub get
flutter analyze
flutter test
```

No code generation step exists on purpose (see the `sqflite` note in the
README). If your change would require one, open an issue first.

## Project conventions

### Layering — keep it one-directional

```
features/  →  core/providers.dart  →  data/repositories  →  core/database
```

* A screen talks to repositories **only** through providers.
* A repository never imports anything from `features/`.
* `AppDatabase` is the only place SQL runs.
* Notifications are scheduled **only** through `ReminderScheduler`, and IDs come
  **only** from `AkashaNotificationIds` (`lib/core/notifications/notification_ids.dart`).

### Files and naming

* `snake_case.dart` files, `PascalCase` classes, `camelCase` members.
* One primary widget per file; private helpers prefixed with `_`.
* Feature folders own their screens and small widgets. Anything used by two or
  more features gets promoted to `lib/shared/widgets/`.

### Design tokens, not magic numbers

* Colours: `AppColors` — never a raw `Color(0x…)` in a feature file.
* Radii/spacing/durations: `AppRadius`, `AppSpacing`, `AppDurations` in
  `lib/core/theme/app_tokens.dart`.
* Shadows: `AppShadows` — tinted with lavender/pink, never pure black.
* Card radius must stay ≥ 20 px; the design-system widget test enforces it.

### Data rules

* IDs are UUID v4 strings; primary keys are `TEXT`.
* All timestamps are epoch milliseconds (`created_at`, `updated_at`,
  `deleted_at`); day buckets are `day_key` in `yyyy-MM-dd` local time.
* Writes set `dirty = 1` so the sync queue can see them.
* Deletes are tombstones (`deleted_at IS NOT NULL`), never hard `DELETE`, for
  anything that participates in sync.

### Copy style

* Lowercase sentence case. Second person. "You" not "the user".
* Warm nouns: *a sip*, *a breath*, *a small note*, *your day*.
* Prefer "no rush" over "don't forget", "when you're ready" over "overdue".

## Adding a screen

1. Create `lib/features/<feature>/<name>_screen.dart`.
2. Wrap in `GradientScaffold`; headers use `AkashaHeader`.
3. Add the route to `lib/core/routing/app_router.dart` **and** to the route-name
   class so navigation stays typed.
4. Add a widget test that at least pumps the screen with overridden providers.
5. If it needs a new table, update `schema.dart`, bump `AppDatabase.version`, and
   write the migration in the same commit.

## Adding a dependency

Dependencies are pinned deliberately; a caret `^` on an untested package is how
builds break for other people.

* Justify it in the PR description (what it replaces, what it costs).
* Pin an exact version that is known to resolve with the current Flutter stable.
* Confirm the licence is compatible with MIT.
* Prefer no dependency: 30 lines of Dart beats 3 MB of native code.

## Tests

* Unit tests for logic (schedule maths, date maths, conflict resolution, copy rules).
* Widget tests for anything that renders.
* Nothing in the test suite may require network, Firebase or a real device.
* Do not weaken a test to make a change pass. If a test encodes a requirement
  (e.g. "16 slots including midnight"), the requirement wins.

## Commits

Conventional-commit style prefixes: `feat:`, `fix:`, `refactor:`, `docs:`,
`test:`, `chore:`. One logical change per commit. Present tense, lowercase
subject, no trailing period.

## Reporting bugs

Please include: Android version, phone model/OEM, app version, whether
notifications worked, battery-optimisation state (Settings → Diagnostics shows
all of it), and what you expected instead. Feelings are welcome in the report —
this app is about feelings.

## Security

Never open a PR containing an API key, a service-account JSON, a signing keystore,
`google-services.json`, or a `.env` with real values. If you find a vulnerability,
do not file a public issue; contact the maintainer privately first.

## Privacy

Any change that adds tracking, analytics, ads, remote logging of user content, or
a third-party SDK that phones home will be rejected. AKASHA's promise is that
nothing leaves the phone unless the owner explicitly turns sync on.
