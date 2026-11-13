/// Small, dependency-free validators used by forms.
abstract final class Validators {
  static String? required(String? v, [String field = 'This field']) {
    if (v == null || v.trim().isEmpty) return '$field is needed';
    return null;
  }

  static String? name(String? v) {
    final empty = required(v, 'A name');
    if (empty != null) return empty;
    if (v!.trim().length < 2) return 'Just a little longer';
    if (v.trim().length > 40) return 'That is a bit long';
    return null;
  }

  static String? positiveNumber(String? v, {int min = 1, int max = 100000}) {
    if (v == null || v.trim().isEmpty) return 'Please add a number';
    final n = num.tryParse(v.trim());
    if (n == null) return 'Numbers only, please';
    if (n < min) return 'Must be at least $min';
    if (n > max) return 'That seems too high';
    return null;
  }

  static String? waterAmount(String? v) {
    final base = positiveNumber(v, min: 20, max: 3000);
    if (base != null) return base;
    final n = int.parse(v!.trim());
    if (n < 50) return 'A glass is usually more than 50 ml';
    if (n > 2000) return 'More than 2 L in one go is unusual';
    return null;
  }

  static String? waterTarget(String? v) {
    final base = positiveNumber(v, min: 500, max: 8000);
    if (base != null) return base;
    return null;
  }

  static String? medicineName(String? v) {
    final base = required(v, 'A medicine name');
    if (base != null) return base;
    if (v!.trim().length > 60) return 'Keep it short and recognisable';
    return null;
  }

  static String? dosage(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    if (v.trim().length > 120) return 'That is a bit long';
    return null;
  }

  /// True when two reminder times in [minutes] are the same minute of day.
  ///
  /// Two doses scheduled for the same minute would both ask "I took it" for a
  /// time the user cannot tell apart, so the form refuses to save the duplicate
  /// rather than creating a reminder she can never answer correctly.
  static bool hasDuplicateMinutes(Iterable<int> minutes) {
    final seen = <int>{};
    for (final m in minutes) {
      if (!seen.add(m)) return true;
    }
    return false;
  }
}
