import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/shared_http_client.dart';

class _RecordingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test(
    'a repository that only borrowed the shared client leaves it open at dispose',
    () {
      final borrowedByRoom = _RecordingClient();
      RoomRepository(client: borrowedByRoom).dispose();
      expect(
        borrowedByRoom.closed,
        isFalse,
        reason:
            'os três repositórios compartilham um cliente só; se qualquer '
            'um fechasse o que apenas pegou emprestado, os outros dois '
            'perdiam a conexão junto',
      );

      final borrowedByHand = _RecordingClient();
      HandInboxRepository(client: borrowedByHand).dispose();
      expect(borrowedByHand.closed, isFalse);

      final borrowedByNetwork = _RecordingClient();
      ConnectivityService(client: borrowedByNetwork).dispose();
      expect(borrowedByNetwork.closed, isFalse);
    },
  );

  test(
    'the room, the hand and the network reach through the same client, not three',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final client = container.read(sharedHttpClientProvider);

      expect(container.read(roomRepositoryProvider).client, same(client));
      expect(container.read(handInboxRepositoryProvider).client, same(client));
      expect(container.read(connectivityServiceProvider).client, same(client));
    },
  );

  test(
    'the shared client stays open long enough to outlive a turn, not the 15 s dart:io default',
    () {
      final socket = newSharedHttpClient();
      addTearDown(socket.close);
      expect(
        socket.idleTimeout,
        const Duration(seconds: 90),
        reason:
            'um valor mais curto volta a abrir um handshake por turno — o '
            'problema que este ticket fecha',
      );
    },
  );
}
