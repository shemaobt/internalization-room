import 'package:flutter_dotenv/flutter_dotenv.dart';

/// What the build was told about the room it serves.
///
/// The address is baked in at build time, so a mistake here is a broken build rather
/// than a bad afternoon — and the room has to be able to say so. It could not: the
/// missing-value throw is a `StateError`, an `Error` and not an `Exception`, and every
/// catch between here and the screen is `on Exception`. A `.env` missing a value
/// looped the invite between offline and touch-me against a perfectly healthy server.
abstract class Env {
  static Future<void> load() => dotenv.load();

  /// Whether the build carries everything the room needs, checked before it opens.
  static bool get complete => _value('BACKEND_URL') != null;

  /// The room's address, without the trailing slash a human will eventually type.
  ///
  /// One extra slash produced `//api/...` and `//health`, which Starlette does not
  /// redirect: every route 404ed, and a 404 is read as a session the server forgot — so
  /// the team was told their session no longer existed.
  static String get backendUrl =>
      _stripTrailingSlashes(_required('BACKEND_URL'));

  static bool get devPularFases =>
      dotenv.isInitialized && _value('DEV_PULAR_FASES') == '1';

  static const devAtalhos = bool.fromEnvironment('DEV_ATALHOS');

  static String _stripTrailingSlashes(String url) {
    var end = url.length;
    while (end > 0 && url[end - 1] == '/') {
      end--;
    }
    return url.substring(0, end);
  }

  static String? _value(String name) {
    final value = dotenv.env[name];
    return value == null || value.isEmpty ? null : value;
  }

  static String _required(String name) {
    final value = _value(name);
    if (value == null) {
      throw StateError(
        '$name is missing from .env — copy .env.example and fill it in',
      );
    }
    return value;
  }
}
