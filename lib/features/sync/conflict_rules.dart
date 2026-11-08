/// Pure conflict-resolution rules for the offline-first sync layer.
///
/// These live in their own file (no Flutter, no Firestore, no SQLite) so the one
/// rule that can silently destroy a user's data is directly testable — see
/// `test/unit/sync_logic_test.dart`.
///
/// The model is **last-writer-wins per record**, with one asymmetry in favour of
/// local work:
///
///  * A clean local row (already uploaded) always accepts whatever the cloud has.
///  * A dirty local row (edited, not yet uploaded) is replaced only if the cloud
///    copy is *strictly newer*. On a tie the local row wins and is re-uploaded,
///    because dropping an unpushed change is the worse failure.
abstract final class SyncConflictRules {
  /// Whether the local row should be replaced by the remote one.
  static bool shouldReplaceLocal({
    required int localUpdatedAt,
    required bool localDirty,
    required int remoteUpdatedAt,
  }) {
    if (!localDirty) return true;
    return remoteUpdatedAt > localUpdatedAt;
  }

  /// Whether the (dirty) local row still needs to be pushed after a pull.
  static bool shouldRequeueLocal({
    required int localUpdatedAt,
    required bool localDirty,
    required int remoteUpdatedAt,
  }) {
    return localDirty && localUpdatedAt >= remoteUpdatedAt;
  }

  /// A tombstone is just a record with a newer `updated_at`, so a deletion made
  /// after an edit wins, and an edit made after a deletion wins. This helper
  /// exists so callers do not have to remember that.
  static bool isDeleted(Map<String, Object?> row) =>
      row['deleted_at'] != null;
}
