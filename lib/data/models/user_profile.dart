import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import 'sync_entity.dart';

class UserProfile with SyncEntity {
  UserProfile({
    required this.id,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.localOnly = true,
    this.firebaseUid,
    this.email,
    this.onboardedAt,
    this.cloudLinkedAt,
  });

  @override
  final String id;
  final String displayName;
  final bool localOnly;
  final String? firebaseUid;
  final String? email;
  final DateTime? onboardedAt;
  final DateTime? cloudLinkedAt;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  bool get isOnboarded => onboardedAt != null;
  bool get isCloudLinked => firebaseUid != null;

  UserProfile copyWith({
    String? displayName,
    bool? localOnly,
    String? firebaseUid,
    String? email,
    DateTime? onboardedAt,
    DateTime? cloudLinkedAt,
    bool? isDirty,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt,
      isDirty: isDirty ?? true,
      localOnly: localOnly ?? this.localOnly,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      email: email ?? this.email,
      onboardedAt: onboardedAt ?? this.onboardedAt,
      cloudLinkedAt: cloudLinkedAt ?? this.cloudLinkedAt,
    );
  }

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'display_name': displayName,
        'local_only': localOnly ? 1 : 0,
        'firebase_uid': firebaseUid,
        'email': email,
        'onboarded_at': SyncEntity.toMillis(onboardedAt),
        'cloud_linked_at': SyncEntity.toMillis(cloudLinkedAt),
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory UserProfile.fromRow(Map<String, Object?> r) => UserProfile(
        id: r['id'] as String,
        displayName: r['display_name'] as String,
        localOnly: (r['local_only'] as int? ?? 1) == 1,
        firebaseUid: r['firebase_uid'] as String?,
        email: r['email'] as String?,
        onboardedAt: SyncEntity.fromMillis(r['onboarded_at']),
        cloudLinkedAt: SyncEntity.fromMillis(r['cloud_linked_at']),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}
