import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import 'sync_entity.dart';

// ─── Mood ──────────────────────────────────────────────────────────────────

enum MoodType {
  happy('happy', 'Happy', 5),
  calm('calm', 'Calm', 4),
  excited('excited', 'Excited', 5),
  sad('sad', 'Sad', 2),
  stressed('stressed', 'Stressed', 2),
  overwhelmed('overwhelmed', 'Overwhelmed', 1),
  tired('tired', 'Tired', 2),
  anxious('anxious', 'Anxious', 1);

  const MoodType(this.key, this.label, this.valence);
  final String key;
  final String label;

  /// Purely a presentation weighting for charts — never a diagnosis.
  final int valence;

  static MoodType? fromKey(String? key) {
    if (key == null) return null;
    for (final m in MoodType.values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

class MoodEntry with SyncEntity {
  MoodEntry({
    required this.id,
    required this.userId,
    required this.dayKey,
    required this.mood,
    required this.loggedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.intensity = 3,
    this.note,
  });

  @override
  final String id;
  final String userId;
  final String dayKey;
  final MoodType mood;
  final int intensity; // 1..5
  final String? note;
  final DateTime loggedAt;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  MoodEntry copyWith({MoodType? mood, int? intensity, String? note}) => MoodEntry(
        id: id,
        userId: userId,
        dayKey: dayKey,
        mood: mood ?? this.mood,
        intensity: intensity ?? this.intensity,
        note: note ?? this.note,
        loggedAt: loggedAt,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'day_key': dayKey,
        'mood': mood.key,
        'intensity': intensity,
        'note': note,
        'logged_at': SyncEntity.toMillis(loggedAt),
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory MoodEntry.fromRow(Map<String, Object?> r) => MoodEntry(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        dayKey: r['day_key'] as String,
        mood: MoodType.fromKey(r['mood'] as String?) ?? MoodType.calm,
        intensity: r['intensity'] as int? ?? 3,
        note: r['note'] as String?,
        loggedAt: AkashaDates.fromMillis(r['logged_at'] as int),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

// ─── Journal ───────────────────────────────────────────────────────────────

class JournalEntry with SyncEntity {
  JournalEntry({
    required this.id,
    required this.userId,
    required this.dayKey,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.createdLocal,
    this.deletedAt,
    this.isDirty = true,
    this.title,
    this.mood,
    this.tags = const [],
    this.isPinned = false,
  });

  @override
  final String id;
  final String userId;
  final String dayKey;
  final String? title;

  /// Stored locally only. Never uploaded unless she explicitly enables sync,
  /// and even then the Firestore path is scoped to her own UID.
  final String body;
  final MoodType? mood;
  final List<String> tags;
  final bool isPinned;
  final DateTime createdLocal;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  JournalEntry copyWith({
    String? title,
    String? body,
    MoodType? mood,
    bool clearMood = false,
    List<String>? tags,
    bool? isPinned,
  }) =>
      JournalEntry(
        id: id,
        userId: userId,
        dayKey: dayKey,
        title: title ?? this.title,
        body: body ?? this.body,
        mood: clearMood ? null : (mood ?? this.mood),
        tags: tags ?? this.tags,
        isPinned: isPinned ?? this.isPinned,
        createdLocal: createdLocal,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'day_key': dayKey,
        'title': title,
        'body': body,
        'mood': mood?.key,
        'tags': tags.join(','),
        'is_pinned': isPinned ? 1 : 0,
        'created_local': SyncEntity.toMillis(createdLocal),
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory JournalEntry.fromRow(Map<String, Object?> r) => JournalEntry(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        dayKey: r['day_key'] as String,
        title: r['title'] as String?,
        body: r['body'] as String,
        mood: MoodType.fromKey(r['mood'] as String?),
        tags: (r['tags'] as String? ?? '')
            .split(',')
            .where((t) => t.trim().isNotEmpty)
            .toList(),
        isPinned: (r['is_pinned'] as int? ?? 0) == 1,
        createdLocal: AkashaDates.fromMillis(r['created_local'] as int),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

// ─── Overthinking reflection ───────────────────────────────────────────────

class Reflection with SyncEntity {
  Reflection({
    required this.id,
    required this.userId,
    required this.dayKey,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.situation,
    this.assumption,
    this.evidenceFor,
    this.alternative,
    this.actionStep,
    this.completed = false,
    this.moodAfter,
  });

  @override
  final String id;
  final String userId;
  final String dayKey;
  final String? situation;
  final String? assumption;
  final String? evidenceFor;
  final String? alternative;
  final String? actionStep;
  final bool completed;
  final MoodType? moodAfter;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'day_key': dayKey,
        'situation': situation,
        'assumption': assumption,
        'evidence_for': evidenceFor,
        'alternative': alternative,
        'action_step': actionStep,
        'completed': completed ? 1 : 0,
        'mood_after': moodAfter?.key,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory Reflection.fromRow(Map<String, Object?> r) => Reflection(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        dayKey: r['day_key'] as String,
        situation: r['situation'] as String?,
        assumption: r['assumption'] as String?,
        evidenceFor: r['evidence_for'] as String?,
        alternative: r['alternative'] as String?,
        actionStep: r['action_step'] as String?,
        completed: (r['completed'] as int? ?? 0) == 1,
        moodAfter: MoodType.fromKey(r['mood_after'] as String?),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

// ─── Gratitude ─────────────────────────────────────────────────────────────

class GratitudeEntry with SyncEntity {
  GratitudeEntry({
    required this.id,
    required this.userId,
    required this.dayKey,
    required this.first,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.second,
    this.third,
  });

  @override
  final String id;
  final String userId;
  final String dayKey;
  final String first;
  final String? second;
  final String? third;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  List<String> get items => [first, if (second != null) second!, if (third != null) third!];

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'day_key': dayKey,
        'first': first,
        'second': second,
        'third': third,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory GratitudeEntry.fromRow(Map<String, Object?> r) => GratitudeEntry(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        dayKey: r['day_key'] as String,
        first: r['first'] as String,
        second: r['second'] as String?,
        third: r['third'] as String?,
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

// ─── Breathing ─────────────────────────────────────────────────────────────

class BreathingSession with SyncEntity {
  BreathingSession({
    required this.id,
    required this.userId,
    required this.dayKey,
    required this.startedAt,
    required this.durationSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.completed = true,
    this.pattern = '4-4-6',
  });

  @override
  final String id;
  final String userId;
  final String dayKey;
  final DateTime startedAt;
  final int durationSeconds;
  final bool completed;
  final String pattern;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'day_key': dayKey,
        'started_at': SyncEntity.toMillis(startedAt),
        'duration_seconds': durationSeconds,
        'completed': completed ? 1 : 0,
        'pattern': pattern,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory BreathingSession.fromRow(Map<String, Object?> r) => BreathingSession(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        dayKey: r['day_key'] as String,
        startedAt: AkashaDates.fromMillis(r['started_at'] as int),
        durationSeconds: r['duration_seconds'] as int,
        completed: (r['completed'] as int? ?? 1) == 1,
        pattern: r['pattern'] as String? ?? '4-4-6',
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

// ─── Motivation ────────────────────────────────────────────────────────────

enum MotivationCategory {
  confidence('confidence', 'Confidence'),
  selfLove('self_love', 'Self-love'),
  overthinking('overthinking', 'Overthinking'),
  productivity('productivity', 'Productivity'),
  calmness('calmness', 'Calmness'),
  gratitude('gratitude', 'Gratitude'),
  courage('courage', 'Courage'),
  growth('growth', 'Personal growth');

  const MotivationCategory(this.key, this.label);
  final String key;
  final String label;

  static MotivationCategory fromKey(String? key) => MotivationCategory.values
      .firstWhere((c) => c.key == key, orElse: () => MotivationCategory.selfLove);
}

class MotivationalMessage with SyncEntity {
  MotivationalMessage({
    required this.id,
    required this.category,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = false,
    this.isFavorite = false,
    this.lastShownAt,
    this.showCount = 0,
    this.source = 'builtin',
  });

  @override
  final String id;
  final MotivationCategory category;
  final String text;
  final bool isFavorite;
  final DateTime? lastShownAt;
  final int showCount;
  final String source;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  MotivationalMessage copyWith({bool? isFavorite, DateTime? lastShownAt, int? showCount}) =>
      MotivationalMessage(
        id: id,
        category: category,
        text: text,
        isFavorite: isFavorite ?? this.isFavorite,
        lastShownAt: lastShownAt ?? this.lastShownAt,
        showCount: showCount ?? this.showCount,
        source: source,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'category': category.key,
        'text': text,
        'is_favorite': isFavorite ? 1 : 0,
        'last_shown_at': SyncEntity.toMillis(lastShownAt),
        'show_count': showCount,
        'source': source,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory MotivationalMessage.fromRow(Map<String, Object?> r) => MotivationalMessage(
        id: r['id'] as String,
        category: MotivationCategory.fromKey(r['category'] as String?),
        text: r['text'] as String,
        isFavorite: (r['is_favorite'] as int? ?? 0) == 1,
        lastShownAt: SyncEntity.fromMillis(r['last_shown_at']),
        showCount: r['show_count'] as int? ?? 0,
        source: r['source'] as String? ?? 'builtin',
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 0) == 1,
      );
}

// ─── Love notes ────────────────────────────────────────────────────────────

class LoveNote with SyncEntity {
  LoveNote({
    required this.id,
    required this.userId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.author = 'Someone who cares',
    this.minuteOfDay = 21 * 60,
    this.enabled = true,
    this.isFavorite = false,
    this.lastDeliveredAt,
    this.deliveryCount = 0,
    this.source = 'local',
  });

  @override
  final String id;
  final String userId;
  final String text;
  final String author;
  final int? minuteOfDay;
  final bool enabled;
  final bool isFavorite;
  final DateTime? lastDeliveredAt;
  final int deliveryCount;
  final String source;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  LoveNote copyWith({
    String? text,
    String? author,
    int? minuteOfDay,
    bool? enabled,
    bool? isFavorite,
    DateTime? lastDeliveredAt,
  }) =>
      LoveNote(
        id: id,
        userId: userId,
        text: text ?? this.text,
        author: author ?? this.author,
        minuteOfDay: minuteOfDay ?? this.minuteOfDay,
        enabled: enabled ?? this.enabled,
        isFavorite: isFavorite ?? this.isFavorite,
        lastDeliveredAt: lastDeliveredAt ?? this.lastDeliveredAt,
        deliveryCount: deliveryCount,
        source: source,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'text': text,
        'author': author,
        'minute_of_day': minuteOfDay,
        'enabled': enabled ? 1 : 0,
        'is_favorite': isFavorite ? 1 : 0,
        'last_delivered_at': SyncEntity.toMillis(lastDeliveredAt),
        'delivery_count': deliveryCount,
        'source': source,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory LoveNote.fromRow(Map<String, Object?> r) => LoveNote(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        text: r['text'] as String,
        author: r['author'] as String? ?? 'Someone who cares',
        minuteOfDay: r['minute_of_day'] as int?,
        enabled: (r['enabled'] as int? ?? 0) == 1,
        isFavorite: (r['is_favorite'] as int? ?? 0) == 1,
        lastDeliveredAt: SyncEntity.fromMillis(r['last_delivered_at']),
        deliveryCount: r['delivery_count'] as int? ?? 0,
        source: r['source'] as String? ?? 'local',
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

// ─── Notification history ──────────────────────────────────────────────────

class NotificationRecord with SyncEntity {
  NotificationRecord({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = false,
    this.refId,
    this.scheduledFor,
    this.deliveredAt,
    this.actionTaken,
    this.actionAt,
  });

  @override
  final String id;
  final String userId;
  final String kind;
  final String? refId;
  final String title;
  final String body;
  final DateTime? scheduledFor;
  final DateTime? deliveredAt;
  final String? actionTaken;
  final DateTime? actionAt;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  NotificationRecord copyWith({String? actionTaken, DateTime? actionAt}) =>
      NotificationRecord(
        id: id,
        userId: userId,
        kind: kind,
        refId: refId,
        title: title,
        body: body,
        scheduledFor: scheduledFor,
        deliveredAt: deliveredAt,
        actionTaken: actionTaken ?? this.actionTaken,
        actionAt: actionAt ?? this.actionAt,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'kind': kind,
        'ref_id': refId,
        'title': title,
        'body': body,
        'scheduled_for': SyncEntity.toMillis(scheduledFor),
        'delivered_at': SyncEntity.toMillis(deliveredAt),
        'action_taken': actionTaken,
        'action_at': SyncEntity.toMillis(actionAt),
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory NotificationRecord.fromRow(Map<String, Object?> r) => NotificationRecord(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        kind: r['kind'] as String,
        refId: r['ref_id'] as String?,
        title: r['title'] as String,
        body: r['body'] as String,
        scheduledFor: SyncEntity.fromMillis(r['scheduled_for']),
        deliveredAt: SyncEntity.fromMillis(r['delivered_at']),
        actionTaken: r['action_taken'] as String?,
        actionAt: SyncEntity.fromMillis(r['action_at']),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 0) == 1,
      );
}

// ─── AI chat ───────────────────────────────────────────────────────────────

class AiMessage with SyncEntity {
  AiMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.content,
    required this.createdLocal,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = false,
    this.flagged = false,
  });

  @override
  final String id;
  final String userId;

  /// 'user' or 'assistant'.
  final String role;
  final String content;
  final DateTime createdLocal;
  final bool flagged;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  bool get isUser => role == 'user';

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'role': role,
        'content': content,
        'created_local': SyncEntity.toMillis(createdLocal),
        'flagged': flagged ? 1 : 0,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory AiMessage.fromRow(Map<String, Object?> r) => AiMessage(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        role: r['role'] as String,
        content: r['content'] as String,
        createdLocal: AkashaDates.fromMillis(r['created_local'] as int),
        flagged: (r['flagged'] as int? ?? 0) == 1,
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 0) == 1,
      );
}
