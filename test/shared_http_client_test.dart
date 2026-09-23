import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/shared_http_client.dart';

void main() {
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
      expect(
        sharedHttpIdleTimeout,
        const Duration(seconds: 90),
        reason:
            'um valor mais curto volta a abrir um handshake por turno — o '
            'problema que este ticket fecha',
      );
    },
  );
}
