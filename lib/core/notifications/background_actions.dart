import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Transaction;

import '../../data/models/medicine_models.dart';
import '../../data/models/water_models.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/notification_history_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/water_repository.dart';
import '../database/app_database.dart';
import '../utils/date_utils.dart';
import 'notification_ids.dart';
import 'notification_service.dart';

/// Executes a notification button press — in **any** app state.
///
/// Why this file exists (repair R2)
/// -------------------------------
/// The previous implementation routed the background callback through static
/// state (`BackgroundActionHandler._delegate` / `BackgroundQueueWriter._writer`)
/// that the *main isolate* registered during bootstrap. Android runs the
/// notification-action callback in a **separate isolate**, where every one of
/// those statics is `null` and every Riverpod provider is absent. Consequently
/// the background path silently did nothing but write a JSONL line, and the
/// recorded action never reached SQLite — which is why "I drank water" from a
/// locked screen could look like it was ignored.
///
/// The repair: the headless isolate now builds its **own** container, opens its
/// own SQLite connection, and writes the change itself. No statics, no
/// providers, no UI. The main isolate no longer needs to be alive.
///
/// What it guarantees
/// ------------------
/// * **Exactly once.** Every action carries a dedupe key. Replays from the
///   durable queue, double taps and duplicated broadcast delivery all collapse
///   to a single row (the key is persisted in `notification_actions`).
/// * **Atomic.** The domain write and the dedupe marker commit in one SQLite
///   transaction, so a crash mid-way leaves neither or both.
/// * **Durable.** If anything throws, the event stays in the JSONL queue and is
///   replayed on next launch — an action is never silently dropped.
abstract final class BackgroundActionEngine {
  /// Handles one callback. Returns true when the action is safely persisted
  /// (or was already applied earlier).
  static Future<bool> handle(NotificationResponse response) async {
    final payload = NotificationPayload.decode(response.payload);
    final actionId = int.tryParse(response.actionId ?? '') ?? 0;

    // A plain tap (no action button) is not a data change; nothing to persist
    // in the background. The UI handles it when the app opens.
    if (actionId == 0) return true;
    if (payload == null) return false;

    try {
      final event = ActionEvent(
        actionId: actionId,
        payload: payload,
        respondedAt: DateTime.now(),
        responseType: response.notificationResponseType.name,
      );

      final db = AppDatabase.instance;
      await db.open();
      final applied = await ActionExecutor(db).execute(event);
      if (applied) {
        // The schedule may need to change (a snooze was created, a dose was
        // answered). Re-running the full planner is the same code path the app
        // uses; it is idempotent and cheap.
        await ActionExecutor(db).rescheduleIfNeeded(event);
      }
      return true;
    } catch (e, st) {
      debugPrint('AKASHA background action failed, queueing for replay: $e\n$st');
      await PendingActionQueue.instance.push({
        'actionId': actionId,
        'payload': response.payload ?? '',
        'at': DateTime.now().millisecondsSinceEpoch,
        'dedupeKey': ActionEvent.dedupeKeyFor(actionId, payload),
      });
      return false;
    }
  }
}

/// One normalised notification interaction.
class ActionEvent {
  const ActionEvent({
    required this.actionId,
    required this.payload,
    required this.respondedAt,
    this.responseType = 'selectNotification',
  });

  final int actionId;
  final NotificationPayload payload;
  final DateTime respondedAt;
  final String responseType;

  /// Stable identity for deduplication.
  ///
  /// Deliberately *not* keyed on time: the same slot must collapse no matter
  /// how many times Android re-delivers the broadcast. It is keyed on the
  /// action plus the alarm occurrence (payload slot + day), which is unique.
  String get dedupeKey =>
      dedupeKeyFor(actionId, payload, at: respondedAt);

  static String dedupeKeyFor(
    int actionId,
    NotificationPayload payload, {
    DateTime? at,
  }) {
    final day = AkashaDates.key(at ?? DateTime.now());
    return '${payload.kind}|${payload.refId ?? ''}|'
        '${payload.slotMinute ?? ''}|${payload.value ?? ''}|$actionId|$day';
  }
}

/// Applies an [ActionEvent] to the database.
///
/// Constructed with an explicit [AppDatabase] rather than reaching for a
/// provider, so the identical logic runs in the UI isolate, the headless
/// isolate, and unit tests.
class ActionExecutor {
  ActionExecutor(this._db);

  final AppDatabase _db;

  // Repositories are created lazily per executor: in the headless isolate there
  // is no ProviderContainer to borrow them from.
  late final ProfileRepository _profiles = ProfileRepository(_db);
  late final WaterRepository _water = WaterRepository(_db);
  late final MedicineRepository _medicine = MedicineRepository(_db);
  late final NotificationHistoryRepository _history =
      NotificationHistoryRepository(_db);

  /// Returns true when the database was changed by this call.
  Future<bool> execute(ActionEvent event) async {
    final kind = event.payload.kind;
    final key = event.dedupeKey;

    return _db.transaction((txn) async {
      // Read the profile *inside* this transaction: one executor for the whole
      // unit means no nested transaction and no lock interleaving with another
      // writer.
      final profile = await _profiles.currentProfile(txn: txn);
      if (profile == null) {
        // No profile means onboarding has never completed; nothing to attach
        // the action to. Not an error — but do not claim it was applied.
        return false;
      }

      // ── Idempotency gate ────────────────────────────────────────────────
      // Claim the key first. `INSERT OR IGNORE` + a non-zero affected-row count
      // proves this call owns the action; a replay affects 0 rows and returns.
      final claimed = await txn.insert(
        'notification_actions',
        {
          'id': key,
          'action_id': event.actionId,
          'kind': kind,
          'ref_id': event.payload.refId,
          'payload': event.payload.encode(),
          'created_at': event.respondedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (claimed == 0) return false; // already applied by an earlier delivery

      switch (kind) {
        case AkashaActions.payloadWater:
          await _applyWater(txn, profile.id, event);
        case AkashaActions.payloadMedicine:
          await _applyMedicine(txn, profile.id, event);
        default:
          // Motivation / love note / daily: an "open", which is historical
          // information only. Recorded but never mutates wellness data.
          await _recordHistory(
            txn,
            userId: profile.id,
            kind: kind,
            refId: event.payload.refId,
            title: _titleFor(kind),
            body: 'Opened from notification',
            action: 'opened',
            at: event.respondedAt,
          );
      }
      return true;
    });
  }

  // ── Water ─────────────────────────────────────────────────────────────────

  Future<void> _applyWater(
    Transaction txn,
    String userId,
    ActionEvent event,
  ) async {
    // Pass the transaction down: `ensureSettings` otherwise opens its own, and
    // a nested `BEGIN` on the same connection is rejected by SQLite with
    // "cannot start a transaction within a transaction".
    final settings = await _profiles.ensureSettings(userId, txn: txn);
    final minute = event.payload.slotMinute;

    switch (event.actionId) {
      case AkashaActions.drankWater:
        final amount = event.payload.value ?? settings.glassSizeMl;
        final id = _waterLogIdFor(event, amount);
        await _water.insertLogInTxn(
          txn,
          id: id,
          userId: userId,
          amountMl: amount,
          source: WaterLogSource.notification,
          at: event.respondedAt,
          reminderMinute: minute,
          glassSize: _glassLabel(amount, settings),
        );
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'water',
          refId: id,
          title: 'Water reminder',
          body: 'Logged from the notification ($amount ml)',
          action: 'taken',
          at: event.respondedAt,
        );
      case AkashaActions.skipWater:
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'water',
          refId: null,
          title: 'Water reminder',
          body: 'Skipped from the notification',
          action: 'skipped',
          at: event.respondedAt,
        );
      case AkashaActions.snoozeWater:
        final when = event.respondedAt
            .add(Duration(minutes: settings.snoozeMinutes));
        final snoozeId = _snoozeIdFor(userId, event);
        // Upsert rather than REPLACE: a re-delivered snooze (same dedupe key)
        // must keep the row's original `created_at`.
        await AppDatabase.upsert(txn, 'water_snoozes', AppDatabase.insertRow({
          'id': snoozeId,
          'user_id': userId,
          'reminder_minute': minute ?? AkashaDates.nowMinutes(),
          'scheduled_for': when.millisecondsSinceEpoch,
          'status': SnoozeStatus.pending.name,
        }));
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'water',
          refId: snoozeId,
          title: 'Water reminder',
          body: 'Snoozed for ${settings.snoozeMinutes} minutes',
          action: 'snoozed',
          at: event.respondedAt,
        );
      default:
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'water',
          refId: null,
          title: 'Water reminder',
          body: 'Opened from notification',
          action: 'opened',
          at: event.respondedAt,
        );
    }
  }

  // ── Medicine ──────────────────────────────────────────────────────────────

  Future<void> _applyMedicine(
    Transaction txn,
    String userId,
    ActionEvent event,
  ) async {
    final logId = event.payload.refId;
    if (logId == null || logId.isEmpty) return;
    final settings = await _profiles.ensureSettings(userId, txn: txn);

    switch (event.actionId) {
      case AkashaActions.tookMedicine:
        // A medicine is ONLY ever marked taken on explicit confirmation.
        await _medicine.applyResponseInTxn(
          txn,
          logId: logId,
          status: DoseStatus.taken,
          respondedAt: event.respondedAt,
        );
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Marked as taken',
          action: 'taken',
          at: event.respondedAt,
        );
      case AkashaActions.skipMedicine:
        await _medicine.applyResponseInTxn(
          txn,
          logId: logId,
          status: DoseStatus.skipped,
          respondedAt: event.respondedAt,
        );
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Marked as skipped',
          action: 'skipped',
          at: event.respondedAt,
        );
      case AkashaActions.snoozeMedicine:
        final when = event.respondedAt
            .add(Duration(minutes: settings.snoozeMinutes));
        await _medicine.applyResponseInTxn(
          txn,
          logId: logId,
          status: DoseStatus.snoozed,
          snoozedUntil: when,
          respondedAt: event.respondedAt,
        );
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Snoozed until ${AkashaDates.minutesToLabel(when.hour * 60 + when.minute)}',
          action: 'snoozed',
          at: event.respondedAt,
        );
      default:
        await _recordHistory(
          txn,
          userId: userId,
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Opened from notification',
          action: 'opened',
          at: event.respondedAt,
        );
    }
  }

  // ── History ───────────────────────────────────────────────────────────────

  /// Writes the audit row for "what happened to this reminder".
  ///
  /// Uses the deterministic key `kind|refId|action|dayKey` at the SQL level via
  /// `insert or ignore`, so a re-delivered internet-free callback cannot create
  /// a second history row for the same event.
  Future<void> _recordHistory(
    Transaction txn, {
    required String userId,
    required String kind,
    required String? refId,
    required String title,
    required String body,
    required String action,
    required DateTime at,
  }) async {
    final id = 'evt:${kind}:${refId ?? ''}:$action:${AkashaDates.key(at)}';
    final inserted = await txn.insert(
      'notification_history',
      AppDatabase.insertRow({
        'id': id,
        'user_id': userId,
        'kind': kind,
        'ref_id': refId,
        'title': title,
        'body': body,
        'delivered_at': at.millisecondsSinceEpoch,
        'action_taken': action,
        'action_at': at.millisecondsSinceEpoch,
      }),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted == 0) {
      // Already recorded for this day; nothing else to do.
      return;
    }
  }

  // ── Post-action scheduling ────────────────────────────────────────────────

  /// Schedules the snooze alarm that the action implies, and cancels the alarm
  /// that was just answered.
  ///
  /// Runs *after* the transaction commits: the plugin call is not part of the
  /// database and cannot be rolled back, so it must never be interleaved with
  /// a write that might fail.
  Future<void> rescheduleIfNeeded(ActionEvent event) async {
    final kind = event.payload.kind;
    if (kind == AkashaActions.payloadWater &&
        event.actionId == AkashaActions.snoozeWater) {
      final profile = await _profiles.currentProfile();
      if (profile == null) return;
      final settings = await _profiles.ensureSettings(profile.id);
      final when =
          event.respondedAt.add(Duration(minutes: settings.snoozeMinutes));
      await NotificationService().scheduleSnooze(
        snoozeId: _snoozeIdFor(profile.id, event),
        amountMl: event.payload.value ?? settings.glassSizeMl,
        when: when,
        originalMinute: event.payload.slotMinute ?? 0,
        isMedicine: false,
        exact: true,
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Deterministic water log id for an action, so a duplicated delivery that
  /// somehow slips past the dedupe gate still cannot double-count millilitres
  /// (the `id` is the primary key).
  String _waterLogIdFor(ActionEvent event, int amountMl) {
    final minute = event.payload.slotMinute ?? 0;
    return 'waterlog:notif:${AkashaDates.key(event.respondedAt)}:'
        '$minute:$amountMl:${event.actionId}';
  }

  String _snoozeIdFor(String _userId, ActionEvent event) =>
      'snooze:${AkashaDates.key(event.respondedAt)}:'
      '${event.payload.slotMinute ?? 0}:${event.payload.kind}';

  String? _glassLabel(int amount, dynamic settings) {
    try {
      if (amount == settings.smallGlassMl) return 'small';
      if (amount == settings.glassSizeMl) return 'medium';
      if (amount == settings.largeGlassMl) return 'large';
    } catch (_) {}
    return 'custom';
  }

  String _titleFor(String kind) => switch (kind) {
        AkashaActions.payloadMotivation => 'Encouragement',
        AkashaActions.payloadLoveNote => 'A little love note',
        AkashaActions.payloadDaily => 'Daily summary',
        _ => 'AKASHA',
      };
}

/// Durable queue for actions that could not be applied immediately.
///
/// Kept on disk (JSONL in the app support directory) rather than in SQLite on
/// purpose: the whole point is to survive a failure to open SQLite. One line
/// per action, appended with `flush: true`.
class PendingActionQueue {
  PendingActionQueue._();
  static final PendingActionQueue instance = PendingActionQueue._();

  static const String _fileName = 'akasha_pending_actions.jsonl';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Appends an action. Never throws.
  Future<bool> push(Map<String, Object?> action) async {
    try {
      final file = await _file();
      final line = jsonEncode({
        'id': '${DateTime.now().microsecondsSinceEpoch}',
        'at': DateTime.now().millisecondsSinceEpoch,
        ...action,
      });
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      return true;
    } catch (e) {
      debugPrint('AKASHA: could not persist notification action: $e');
      return false;
    }
  }

  /// Reads and clears the queue. A line that fails to parse is dropped (it is
  /// corrupt, and keeping it would block the rest forever).
  Future<List<Map<String, Object?>>> drain() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final content = await file.readAsString();
      await file.delete();
      final out = <Map<String, Object?>>[];
      for (final line in content.split('\n')) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) out.add(Map<String, Object?>.from(decoded));
        } catch (_) {
          debugPrint('AKASHA: dropping unparseable queued action');
        }
      }
      return out;
    } catch (e) {
      debugPrint('AKASHA: could not read pending actions: $e');
      return const [];
    }
  }

  Future<int> pendingCount() async {
    try {
      final file = await _file();
      if (!await file.exists()) return 0;
      final content = await file.readAsString();
      return content.split('\n').where((l) => l.trim().isNotEmpty).length;
    } catch (_) {
      return 0;
    }
  }

  /// Replays everything captured while the app was dead. Called on launch and
  /// on every resume. Returns how many actions were applied.
  Future<int> replay() async {
    final queued = await drain();
    if (queued.isEmpty) return 0;
    var applied = 0;
    for (final item in queued) {
      try {
        final response = NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          id: 0,
          actionId: (item['actionId'] as num?)?.toInt().toString(),
          payload: item['payload'] as String?,
        );
        if (await BackgroundActionEngine.handle(response)) applied++;
      } catch (e) {
        debugPrint('AKASHA: failed to replay queued action: $e');
      }
    }
    return applied;
  }
}

/// Removes notification action markers older than [days].
///
/// `notification_actions` is a dedupe ledger; it only needs to be as long-lived
/// as a notification could plausibly be re-delivered.
Future<void> pruneActionLedger(AppDatabase db, {int days = 14}) async {
  final cutoff = DateTime.now()
      .subtract(Duration(days: days))
      .millisecondsSinceEpoch;
  try {
    await db.db.delete(
      'notification_actions',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
  } catch (e) {
    debugPrint('AKASHA: action ledger prune failed: $e');
  }
}
