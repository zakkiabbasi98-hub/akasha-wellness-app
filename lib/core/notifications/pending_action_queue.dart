import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Durable queue for notification button taps that arrive in a background
/// isolate.
///
/// Why this exists: when Android fires a notification action while the app is
/// terminated, the callback runs in a headless isolate. Opening SQLite there is
/// possible but fragile across OEMs. So the callback does the smallest possible
/// robust thing — append one line to a JSONL file in the app's support
/// directory — and the main isolate drains the queue into the real database as
/// soon as it runs (app open, or the next time any provider refreshes).
///
/// Result: "I drank water" from a locked screen is never lost, and the totals
/// stay consistent with the database.
class PendingActionQueue {
  PendingActionQueue._();
  static final PendingActionQueue instance = PendingActionQueue._();

  static const String _fileName = 'akasha_pending_actions.jsonl';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Called from the background isolate. Never throws.
  Future<bool> push(Map<String, Object?> action) async {
    try {
      final file = await _file();
      final line = '${jsonEncode({
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'at': DateTime.now().millisecondsSinceEpoch,
            ...action,
          })}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      return true;
    } catch (e) {
      debugPrint('AKASHA: could not persist notification action: $e');
      return false;
    }
  }

  /// Reads and clears all queued actions. Safe to call often.
  Future<List<Map<String, Object?>>> drain() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final content = await file.readAsString();
      await file.delete();
      return content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            try {
              return jsonDecode(l) as Map<String, Object?>;
            } catch (_) {
              return <String, Object?>{};
            }
          })
          .where((m) => m.isNotEmpty)
          .toList();
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
}
