import '../../core/utils/date_utils.dart';

/// Mixin for every row that participates in offline-first sync.
///
/// Keeping `updatedAt`/`dirty` on the model (not just the row) lets the sync
/// engine compare local vs cloud timestamps per record and decide
/// last-writer-wins per field-group, which is the conflict rule documented in
/// docs/ARCHITECTURE.md.
mixin SyncEntity {
  String get id;
  DateTime get createdAt;
  DateTime get updatedAt;
  DateTime? get deletedAt;

  /// True when this record has local changes not yet acknowledged by cloud.
  bool get isDirty;

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toRow();

  static int? toMillis(DateTime? d) => d?.millisecondsSinceEpoch;

  static DateTime? fromMillis(Object? v) =>
      v == null ? null : AkashaDates.fromMillis(v as int);
}
