import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Globally unique, sortable-ish identifiers for every synced record.
///
/// Using UUIDv4 for every entity (not autoincrement integers) is what makes
/// offline-first synchronisation possible: a record created on the phone while
/// offline can be uploaded later without id collisions on another device.
abstract final class Ids {
  static String newId() => _uuid.v4();

  /// Deterministic **database row** id for recurring schedule rows, so
  /// regenerating a schedule never creates duplicates (the unique indexes in
  /// `schema.dart` then make a double-run harmless).
  ///
  /// Note: these are row ids, not notification ids. Notification ids are
  /// `int`s and come only from `AkashaNotificationIds` — there is deliberately
  /// no second hashing scheme here, because two schemes is how an app ends up
  /// scheduling the same reminder twice.
  static String slotId(String scope, String key) => '$scope:$key';
}
