import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import 'shared_http_client.dart';

const _pingTimeout = Duration(seconds: 6);

class ConnectivityService {
  final http.Client _client;
  final bool _ownsClient;

  ConnectivityService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  http.Client get client => _client;

  Future<bool> ping() async {
    try {
      final response = await _client
          .get(Uri.parse('${Env.backendUrl}/health'))
          .timeout(_pingTimeout);
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService(
    client: ref.watch(sharedHttpClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
