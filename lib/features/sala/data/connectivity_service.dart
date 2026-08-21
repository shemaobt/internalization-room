import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';

const _pingTimeout = Duration(seconds: 6);
const _radioAnswerTimeout = Duration(seconds: 4);
const _quietBetweenSignals = Duration(seconds: 3);

class ConnectivityService {
  final Connectivity _connectivity;
  final http.Client _client;
  Future<bool>? _inFlight;
  DateTime? _lastSignal;

  ConnectivityService({Connectivity? connectivity, http.Client? client})
      : _connectivity = connectivity ?? Connectivity(),
        _client = client ?? http.Client();

  Future<bool> canReachRoom() {
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  Future<bool> _check() async {
    if (!await _radioSeesSomething()) return false;
    return _pingBackend();
  }

  Future<bool> _radioSeesSomething() async {
    try {
      final results =
          await _connectivity.checkConnectivity().timeout(_radioAnswerTimeout);
      return results.any((result) => result != ConnectivityResult.none);
    } on Object {
      return true;
    }
  }

  Future<bool> _pingBackend() async {
    try {
      final response = await _client
          .get(Uri.parse('${Env.backendUrl}/health'))
          .timeout(_pingTimeout);
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  Stream<void> get onNetworkReturned => _connectivity.onConnectivityChanged
      .where((results) => results.any((result) => result != ConnectivityResult.none))
      .where((_) => _settled())
      .map((_) {});

  bool _settled() {
    final now = DateTime.now();
    final previous = _lastSignal;
    if (previous != null && now.difference(previous) < _quietBetweenSignals) {
      return false;
    }
    _lastSignal = now;
    return true;
  }

  void dispose() => _client.close();
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});
