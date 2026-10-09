import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _linked = RememberedLink(
  deviceId: 'aparelho-1',
  team: TeamLink(projectId: 'equipe-1'),
  credential: 'credencial-1',
);

const _revoked = Refused(RefusalCode.deviceRevoked);

http.Response _revokedAnswer() => http.Response(
  jsonEncode({'detail': 'revoked', 'code': 'DEVICE_REVOKED'}),
  403,
);

typedef _Tablet = ({
  SalaHarness harness,
  ProviderContainer container,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
});

Future<_Tablet> _linkedTablet(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(deviceLinkProvider.notifier).findTheTeam();
  return (
    harness: harness,
    container: container,
    notifier: container.read(salaSessionProvider.notifier),
    read: () => container.read(salaSessionProvider),
  );
}

Future<void> _inAPassage(_Tablet tablet) async {
  await enterThePassage(tablet.notifier, tablet.read, 'P01');
  await waitFor(
    'the opening to rest at the invite',
    () =>
        tablet.read().voice == VoiceState.invite &&
        !tablet.read().awaitingTheGuide,
  );
  await settle();
}

Future<void> _theTeamSpeaks(_Tablet tablet) async {
  tablet.notifier.conversaTap();
  await waitFor(
    'the team to be heard',
    () => tablet.read().voice == VoiceState.listening,
  );
  tablet.notifier.conversaTap();
  await waitFor(
    'the turn to leave the tablet',
    () => tablet.harness.room.calls.contains('sendTurn'),
  );
}

Future<void> _aFreshCodeShows(_Tablet tablet) => waitFor(
  'a fresh claim code to show',
  () => tablet.container.read(deviceLinkProvider).code != null,
);

void _theLinkIsForgotten(_Tablet tablet) {
  final remembered = tablet.harness.vinculo.remembered;
  expect(
    remembered.credential,
    isNull,
    reason:
        'uma credencial revogada guardada é uma que o tablet segue mandando',
  );
  expect(remembered.team, isNull);
  expect(tablet.container.read(deviceLinkProvider).linked, isFalse);
  expect(tablet.harness.room.presented, isNull);
}

File _aRecording() {
  final home = Directory.systemTemp.createTempSync('sala-revogada');
  addTearDown(() => home.deleteSync(recursive: true));
  return File('${home.path}/parte.m4a')..writeAsBytesSync([1, 2, 3]);
}

void main() {
  setUp(() => dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local'));

  test(
    'a DeviceRevoked refusal forgets the link and shows a fresh claim code',
    () async {
      final currentSession = FakeCurrentSessionLedger();
      final tablet = await _linkedTablet(
        SalaHarness(linkedAs: _linked, currentSession: currentSession),
      );
      await _inAPassage(tablet);
      expect(currentSession.held, isNotNull);

      tablet.harness.room.failWith = _revoked;
      await _theTeamSpeaks(tablet);
      await _aFreshCodeShows(tablet);
      await settle();

      _theLinkIsForgotten(tablet);
      expect(
        currentSession.held,
        isNull,
        reason: 'a sessão era da equipe de antes do desvínculo (ADR 0064)',
      );
      expect(
        tablet.harness.room.codesAskedFor,
        [null],
        reason:
            'um código, e um só, para um aparelho novo: cada pedido que a sala '
            'recusou depois da revogação não pode pedir outro',
      );
    },
  );

  test('a plain 401 halts the room and keeps the link', () async {
    final tablet = await _linkedTablet(SalaHarness(linkedAs: _linked));
    await _inAPassage(tablet);

    tablet.harness.room.failWith = const Refused(RefusalCode.unauthorized);
    await _theTeamSpeaks(tablet);
    await waitFor('a person to be called', () => tablet.read().needsPerson);
    await settle();

    expect(tablet.harness.vinculo.remembered.credential, 'credencial-1');
    expect(tablet.harness.vinculo.remembered.team?.projectId, 'equipe-1');
    expect(tablet.container.read(deviceLinkProvider).linked, isTrue);
    expect(
      tablet.harness.room.codesAskedFor,
      isEmpty,
      reason:
          'um 401 sem a revogação não diz que o vínculo acabou; esquecê-lo '
          'manda a equipe de volta à instalação por um erro do servidor',
    );
  });

  test('a revoked take upload forgets the link too', () async {
    final tablet = await _linkedTablet(SalaHarness(linkedAs: _linked));
    await tablet.harness.takes.enqueue(
      _aRecording(),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'passagem',
    );

    tablet.harness.room.failWith = _revoked;
    await tablet.harness.takes.flush();
    await _aFreshCodeShows(tablet);

    expect(tablet.harness.room.calls, contains('sendTake'));
    _theLinkIsForgotten(tablet);
  });

  test('a revoked question forgets the link too', () async {
    final inbox = HandInboxRepository(
      client: MockClient((_) async => _revokedAnswer()),
      deviceId: () async => 'aparelho-hex',
    );
    addTearDown(inbox.dispose);
    final tablet = await _linkedTablet(
      SalaHarness(linkedAs: _linked, inboxService: inbox),
    );

    await tablet.container
        .read(handInboxRepositoryProvider)
        .sendQuestion('sessao-1', _aRecording());
    await _aFreshCodeShows(tablet);

    _theLinkIsForgotten(tablet);
  });

  test('the room repository announces a revocation it was answered, and no '
      'other refusal', () async {
    var status = 403;
    final repository = RoomRepository(
      client: MockClient(
        (_) async => status == 403
            ? _revokedAnswer()
            : http.Response(jsonEncode({'detail': 'no'}), status),
      ),
    );
    addTearDown(repository.dispose);
    var announced = 0;
    final listening = repository.revoked.listen((_) => announced++);
    addTearDown(listening.cancel);

    await repository.fetchState('sessao-1');
    await settle(Duration.zero);
    expect(announced, 1);

    await expectLater(
      repository.openClip('/voice/p01'),
      throwsA(isA<Refused>()),
    );
    await settle(Duration.zero);
    expect(
      announced,
      2,
      reason:
          'o canal e a fala chegam por uma porta transmitida, e também ouvem',
    );

    status = 401;
    await repository.fetchState('sessao-1');
    await settle(Duration.zero);
    expect(
      announced,
      2,
      reason: 'só a revogação fala do vínculo; um 401 comum para a sala',
    );
  });

  test(
    'the hand inbox repository announces a revocation it was answered',
    () async {
      final inbox = HandInboxRepository(
        client: MockClient((_) async => _revokedAnswer()),
        deviceId: () async => 'aparelho-hex',
      );
      addTearDown(inbox.dispose);
      var announced = 0;
      final listening = inbox.revoked.listen((_) => announced++);
      addTearDown(listening.cancel);

      await inbox.fetchReplies();
      await settle(Duration.zero);

      expect(announced, 1);
    },
  );

  testWidgets('a relinked tablet opens the room again without a relaunch', (
    tester,
  ) async {
    final harness = SalaHarness(
      linkedAs: _linked,
      linkPoll: const Duration(milliseconds: 50),
    );
    final container = await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(EscolhaView), findsOneWidget);

    harness.room.failWith = _revoked;
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CodigoView), findsOneWidget);

    harness.room
      ..failWith = null
      ..linkedTo = const TeamLink(projectId: 'equipe-2');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CodigoView), findsNothing);
    expect(find.byType(EscolhaView), findsOneWidget);
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'a sala que parou na revogação é a do vínculo de antes; revinculado, '
          'o tablet volta a trabalhar sem ninguém precisar reabrir o app',
    );
  });
}
