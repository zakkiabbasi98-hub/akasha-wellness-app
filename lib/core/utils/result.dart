/// Tiny Result type so repositories can fail without throwing across layers.
///
/// Flutter UI then renders a calm error state instead of a red screen.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(String message, {Object? cause}) = Err<T>;

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
  String? get errorOrNull => this is Err<T> ? (this as Err<T>).message : null;

  R when<R>({
    required R Function(T value) ok,
    required R Function(String message) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>(:final value) => ok(value),
      Err<T>(:final message) => err(message),
    };
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.message, {this.cause});
  final String message;
  final Object? cause;
}
