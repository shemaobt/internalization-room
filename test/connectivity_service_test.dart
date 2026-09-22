import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';

class FakeConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  void emit() => _changes.add([ConnectivityResult.wifi]);

  void close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  test('a burst of checks becomes a single request to the room', () async {
    var requests = 0;
    final connectivity = FakeConnectivity();
    addTearDown(connectivity.close);
    final service = ConnectivityService(
      connectivity: connectivity,
      client: MockClient((request) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('ok', 200);
      }),
    );
    addTearDown(service.dispose);

    final answers = await Future.wait(
      List.generate(50, (_) => service.reachRoom()),
    );

    expect(answers, everyElement(RoomReach.fine));
    expect(
      requests,
      1,
      reason:
          'cinquenta perguntas ao mesmo tempo derrubam justamente a sala '
          'que elas queriam alcançar',
    );
  });

  test('a later check is asked again, not answered from memory', () async {
    var requests = 0;
    final connectivity = FakeConnectivity();
    addTearDown(connectivity.close);
    final service = ConnectivityService(
      connectivity: connectivity,
      client: MockClient((request) async {
        requests++;
        return http.Response('ok', 200);
      }),
    );
    addTearDown(service.dispose);

    await service.reachRoom();
    await service.reachRoom();

    expect(requests, 2);
  });

  test('a storm of system signals is heard as one', () async {
    final connectivity = FakeConnectivity();
    addTearDown(connectivity.close);
    final service = ConnectivityService(
      connectivity: connectivity,
      client: MockClient((_) async => http.Response('ok', 200)),
    );
    addTearDown(service.dispose);

    var heard = 0;
    final subscription = service.onNetworkReturned.listen((_) => heard++);
    addTearDown(subscription.cancel);

    for (var i = 0; i < 200; i++) {
      connectivity.emit();
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      heard,
      1,
      reason:
          'o iOS repete o aviso de rede sem parar; cada repetição virava '
          'uma consulta ao servidor',
    );
  });

  test('listening again does not buy a fresh signal', () async {
    final connectivity = FakeConnectivity();
    addTearDown(connectivity.close);
    final service = ConnectivityService(
      connectivity: connectivity,
      client: MockClient((_) async => http.Response('ok', 200)),
    );
    addTearDown(service.dispose);

    var heard = 0;
    for (var round = 0; round < 20; round++) {
      final subscription = service.onNetworkReturned.listen((_) => heard++);
      connectivity.emit();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
    }

    expect(
      heard,
      1,
      reason:
          'a sala reassina esse aviso toda vez que cai; se reassinar '
          'zerasse a espera, cair e voltar viraria um laço fechado',
    );
  });

  test(
    'a network that works with no room on it is not a network that is gone',
    () async {
      final connectivity = FakeConnectivity()
        ..current = [ConnectivityResult.wifi];
      addTearDown(connectivity.close);
      final service = ConnectivityService(
        connectivity: connectivity,
        client: MockClient((_) async => http.Response('nao', 404)),
      );
      addTearDown(service.dispose);

      expect(
        await service.reachRoom(),
        RoomReach.roomSilent,
        reason:
            'endereço errado no wi-fi do local produzia a mesma resposta que um '
            'tablet sem rede nenhuma, e a sala dizia que a internet tinha caído',
      );
    },
  );

  test('no interface at all never reaches for the network', () async {
    var requests = 0;
    final connectivity = FakeConnectivity()
      ..current = [ConnectivityResult.none];
    addTearDown(connectivity.close);
    final service = ConnectivityService(
      connectivity: connectivity,
      client: MockClient((_) async {
        requests++;
        return http.Response('ok', 200);
      }),
    );
    addTearDown(service.dispose);

    expect(await service.reachRoom(), RoomReach.noNetwork);
    expect(requests, 0);
  });
}
