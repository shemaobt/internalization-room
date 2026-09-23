import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const sharedHttpIdleTimeout = Duration(seconds: 90);

final sharedHttpClientProvider = Provider<http.Client>((ref) {
  final client = IOClient(HttpClient()..idleTimeout = sharedHttpIdleTimeout);
  ref.onDispose(client.close);
  return client;
});
