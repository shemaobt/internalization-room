import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const sharedHttpIdleTimeout = Duration(seconds: 90);

/// The socket behind the shared client, built here so what it is built with can be read.
HttpClient newSharedHttpClient() =>
    HttpClient()..idleTimeout = sharedHttpIdleTimeout;

final sharedHttpClientProvider = Provider<http.Client>((ref) {
  final client = IOClient(newSharedHttpClient());
  ref.onDispose(client.close);
  return client;
});
