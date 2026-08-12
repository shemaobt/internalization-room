import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract class Env {
  static Future<void> load() => dotenv.load();

  static String get backendUrl => _required('BACKEND_URL');

  static String get roomKey => _required('INTERNALIZATION_ROOM_KEY');

  static String _required(String name) {
    final value = dotenv.env[name];
    if (value == null || value.isEmpty) {
      throw StateError('$name is missing from .env — copy .env.example and fill it in');
    }
    return value;
  }
}
