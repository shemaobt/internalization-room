import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show settle;

const _oneSecond = Duration(seconds: 1);
const _quickPoll = Duration(milliseconds: 20);

/// One answer every route's reader accepts, so a case about headers never turns into a
/// case about response shapes.
String _anyAnswer() => jsonEncode({
      'session_id': 'sessao-1',
      'device_id': 'aparelho-1',
      'code': 'QHF-3M7K',
      'project_id': 'equipe-terena',
      'take_id': 'tomada-1',
      'credential': 'credencial-1',
    });

typedef _Request = Future<void> Function(RoomRepository room, File audio);

/// Every way the room touches the network, named as the app names it.
///
/// The header belongs to the tablet, not to a route, so a case that checks one method is
/// a case that proves nothing about the next one. `noRequestSlipsOut` below reads the
/// repository and fails when a method is added without a line here.
final Map<String, _Request> _everyRequest = {
  'askForACode': (room, _) => room.askForACode('aparelho-1'),
  'readTheLink': (room, _) => room.readTheLink('aparelho-1'),
  'collectTheCredential': (room, _) => room.collectTheCredential('aparelho-1'),
  'createSession': (room, _) => room.createSession(language: 'pt'),
  'passagesOf': (room, _) => room.passagesOf('rute', language: 'pt'),
  'fetchState': (room, _) => room.fetchState('sessao-1'),
  'openSession': (room, _) => room.openSession('sessao-1'),
  'sendTurn': (room, audio) => room.sendTurn('sessao-1', audio),
  'sendChunk': (room, audio) => room.sendChunk(
        'sessao-1',
        audio,
        takeId: 'tomada-1',
        from: Duration.zero,
        to: _oneSecond,
      ),
  'sendTake': (room, audio) =>
      room.sendTake('sessao-1', audio, kind: 'ensaio', scope: 'passagem'),
  'takesOf': (room, _) => room.takesOf('sessao-1'),
  'divideSegment': (room, _) =>
      room.divideSegment('sessao-1', 'trecho-1', at: _oneSecond),
  'replaceSegment': (room, audio) => room.replaceSegment(
        'sessao-1',
        'trecho-1',
        audio,
        takeId: 'tomada-1',
        from: Duration.zero,
        to: _oneSecond,
      ),
  'restartBackTranslation': (room, _) => room.restartBackTranslation('sessao-1'),
  'askForAPerson': (room, _) => room.askForAPerson('sessao-1'),
  'askForAPersonWithoutASession': (room, _) =>
      room.askForAPersonWithoutASession('aparelho-1'),
  'personArrived': (room, _) => room.personArrived('sessao-1'),
  'finishBackTranslation': (room, _) => room.finishBackTranslation('sessao-1', playedByTake: const []),
  'fetchClip': (room, _) => room.fetchClip('/voice/p01'),
  'approveRelease': (room, _) => room.approveRelease('sessao-1'),
};

typedef _InboxRequest = Future<void> Function(HandInboxRepository inbox, File audio);

/// The hand's own way to the room, which keeps a client and a header of its own.
///
/// It is a second repository, so the credential does not reach it by reaching the first
/// one — and once ENG-455 retires the shared key, a question carrying nothing that names
/// the tablet is a question the room stops accepting.
final Map<String, _InboxRequest> _everyInboxRequest = {
  'fetchReplies': (inbox, _) => inbox.fetchReplies(),
  'markHeard': (inbox, _) => inbox.markHeard('resposta-1'),
  'sendQuestion': (inbox, audio) => inbox.sendQuestion('sessao-1', audio),
};

late Directory _support;
late File _recording;

ProviderContainer _tablet({
  required RoomRepository room,
  required LinkedTeam ledger,
  HandInboxRepository? inbox,
  Duration? linkPoll,
}) =>
    ProviderContainer(
      overrides: [
        roomRepositoryProvider.overrideWithValue(room),
        linkedTeamProvider.overrideWithValue(ledger),
        linkPollIntervalProvider.overrideWithValue(linkPoll),
        roomRetryBackoffProvider.overrideWithValue(const [_quickPoll]),
        if (inbox != null) handInboxRepositoryProvider.overrideWithValue(inbox),
      ],
    );

HandInboxRepository _inboxSeenBy(List<http.BaseRequest> seen) {
  final inbox = HandInboxRepository(
    client: MockClient((request) async {
      seen.add(request);
      return http.Response(_anyAnswer(), 200);
    }),
    deviceId: () async => 'aparelho-hex',
  );
  addTearDown(inbox.dispose);
  return inbox;
}

LinkedTeam _ledgerOnDisk() {
  final home = Directory.systemTemp.createTempSync('sala-credencial');
  addTearDown(() => home.deleteSync(recursive: true));
  return LinkedTeam(home: () async => home, vault: FakeCredentialVault());
}

/// A tablet that already knows whose it is and has never held a credential.
///
/// The refusals are answered *after* the link is learnt, so a case that starts from an
/// unclaimed tablet cannot tell "sent back to a new code" from "never left one".
Future<LinkedTeam> _alreadyLinked() async {
  final ledger = _ledgerOnDisk();
  await ledger.rememberDevice('aparelho-1');
  await ledger.rememberTeam(const TeamLink(projectId: 'equipe-terena'));
  return ledger;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
    _support = Directory.systemTemp.createTempSync('sala-aparelho');
    _recording = File('${_support.path}/ensaio.m4a')..writeAsBytesSync([1, 2, 3]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => _support.path,
    );
  });

  tearDownAll(() => _support.deleteSync(recursive: true));

  group('once the tablet holds a credential', () {
    for (final entry in _everyRequest.entries) {
      test('${entry.key} presents it, and still presents the room key', () async {
        final seen = <http.BaseRequest>[];
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen.add(request);
            return http.Response(_anyAnswer(), 200);
          }),
        )..presents('credencial-1');
        addTearDown(repository.dispose);

        await entry.value(repository, _recording);

        expect(seen.single.headers['X-Device-Credential'], 'credencial-1',
            reason: 'uma rota sem a credencial é uma rota que o servidor julga pela '
                'chave compartilhada, que é exatamente o que a credencial existe '
                'para substituir');
        expect(seen.single.headers['X-Room-Key'], 'k',
            reason: 'aposentar a chave é ENG-455; até lá as duas viajam juntas');
      });
    }

    for (final entry in _everyInboxRequest.entries) {
      test('the hand presents it in ${entry.key} too', () async {
        final seen = <http.BaseRequest>[];
        final inbox = _inboxSeenBy(seen)..presents('credencial-1');

        await entry.value(inbox, _recording);

        expect(seen.single.headers['X-Device-Credential'], 'credencial-1');
        expect(seen.single.headers['X-Room-Key'], 'k');
      });
    }
  });

  group('before the tablet holds a credential', () {
    for (final entry in _everyRequest.entries) {
      test('${entry.key} presents none', () async {
        final seen = <http.BaseRequest>[];
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen.add(request);
            return http.Response(_anyAnswer(), 200);
          }),
        );
        addTearDown(repository.dispose);

        await entry.value(repository, _recording);

        expect(seen.single.headers.containsKey('X-Device-Credential'), isFalse,
            reason: 'um cabeçalho vazio é um aparelho afirmando ser alguém, e o '
                'servidor passa a julgá-lo por uma credencial que não existe');
        expect(seen.single.headers['X-Room-Key'], 'k');
      });
    }

    for (final entry in _everyInboxRequest.entries) {
      test('the hand presents none in ${entry.key} either', () async {
        final seen = <http.BaseRequest>[];
        final inbox = _inboxSeenBy(seen);

        await entry.value(inbox, _recording);

        expect(seen.single.headers.containsKey('X-Device-Credential'), isFalse);
        expect(seen.single.headers['X-Room-Key'], 'k');
      });
    }
  });

  for (final (file, enumerated) in [
    ('lib/features/sala/data/room_repository.dart', _everyRequest.keys),
    ('lib/features/sala/data/hand_inbox_repository.dart', _everyInboxRequest.keys),
  ]) {
    test('no request in $file slips out of the enumeration above', () {
      final source = File(file).readAsStringSync();
      final signature = RegExp(r'^  Future<.+> (\w+)\(', multiLine: true);
      final declared = signature
          .allMatches(source)
          .map((match) => match.group(1)!)
          .where((name) => !name.startsWith('_'))
          .toSet();

      expect(
        RegExp(r'^  Future<.*\(.*$', multiLine: true)
            .allMatches(source)
            .map((match) => match.group(0)!)
            .where((line) => !signature.hasMatch(line))
            .toList(),
        isEmpty,
        reason: 'uma assinatura que a regex não sabe ler sai da conta em silêncio, '
            'e o método volta a ser um que ninguém mede',
      );
      expect(declared.difference(enumerated.toSet()), isEmpty,
          reason: 'um método novo sem linha na tabela acima é um método cujo '
              'cabeçalho ninguém mede, e a falta só aparece contra o servidor');
    });
  }

  test('a tablet that learns its team collects a credential, once', () async {
    final ledger = _ledgerOnDisk();
    final room = FakeRoom()..linkedTo = const TeamLink(projectId: 'equipe-terena');
    final container = _tablet(room: room, ledger: ledger, linkPoll: _quickPoll);
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'a credencial ser guardada',
      () async => (await ledger.read()).credential != null,
    );

    expect(room.credentialsCollected, ['aparelho-1']);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await settle();

    expect(room.credentialsCollected, ['aparelho-1'],
        reason: 'o servidor entrega a credencial uma única vez; um segundo pedido '
            'volta 403 e derruba o vínculo de uma sala que já está trabalhando');
  });

  test('a room not ready to hand the credential over keeps the tablet where it is',
      () async {
    final ledger = await _alreadyLinked();
    final room = FakeRoom()
      ..linkedTo = const TeamLink(projectId: 'equipe-terena')
      ..refuseCredentialWith = const CredentialNotYet();
    final container = _tablet(room: room, ledger: ledger, linkPoll: _quickPoll);
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'a segunda tentativa de recolher',
      () => room.credentialsCollected.length > 1,
    );

    expect(container.read(deviceLinkProvider).code, isNull,
        reason: 'um 409 é temporário; mostrar código devolve a tela da instalação '
            'a uma equipe que só precisa esperar');
    expect(container.read(deviceLinkProvider).team?.projectId, 'equipe-terena');
    final remembered = await ledger.read();
    expect(remembered.deviceId, 'aparelho-1');
    expect(remembered.team?.projectId, 'equipe-terena');
  });

  test('a credential already collected sends the tablet back to a new code', () async {
    final ledger = await _alreadyLinked();
    final room = FakeRoom()
      ..linkedTo = const TeamLink(projectId: 'equipe-terena')
      ..refuseCredentialWith = const CredentialTaken();
    final container = _tablet(room: room, ledger: ledger);
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'um código novo aparecer',
      () => container.read(deviceLinkProvider).code != null,
    );

    expect(container.read(deviceLinkProvider).team, isNull);
    expect((await ledger.read()).team, isNull,
        reason: 'a única cópia da credencial se perdeu; seguir com a equipe '
            'guardada deixa o aparelho preso a um vínculo que ele não sabe provar');
    expect(room.codesAskedFor.last, isNull,
        reason: 'o pedido tem de abandonar o aparelho antigo — pedir código para o '
            'mesmo id devolve a mesma linha, cuja credencial já foi entregue');
  });

  test('a tablet linked before the credential existed collects one on its next start',
      () async {
    final ledger = await _alreadyLinked();

    final seen = <http.BaseRequest>[];
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen.add(request);
        return http.Response(_anyAnswer(), 200);
      }),
    );
    addTearDown(repository.dispose);
    final asked = <http.BaseRequest>[];
    final inbox = _inboxSeenBy(asked);
    final container = _tablet(
      room: repository,
      ledger: ledger,
      inbox: inbox,
      linkPoll: _quickPoll,
    );
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'a credencial ser guardada',
      () async => (await ledger.read()).credential != null,
    );
    expect(seen.map((request) => request.url.path),
        contains(endsWith('/devices/aparelho-1/credential')));
    seen.clear();
    await repository.fetchState('sessao-1');
    await inbox.fetchReplies();

    expect(seen.single.headers['X-Device-Credential'], 'credencial-1',
        reason: 'um tablet vinculado antes desta mudança nunca recolheria nada, e '
            'seguiria julgado pela chave compartilhada para sempre');
    expect(asked.single.headers['X-Device-Credential'], 'credencial-1',
        reason: 'a mão tem cliente e cabeçalho próprios: uma credencial que chega '
            'só ao repositório da sala deixa a pergunta da equipe como a única '
            'coisa que ainda chega sem nome');
  });

  test('a credential the tablet already holds outlives the app closing', () async {
    final ledger = _ledgerOnDisk();
    final firstRoom = FakeRoom()
      ..linkedTo = const TeamLink(projectId: 'equipe-terena');
    final firstRun =
        _tablet(room: firstRoom, ledger: ledger, linkPoll: _quickPoll);
    await firstRun.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'a credencial ser guardada',
      () async => (await ledger.read()).credential != null,
    );
    firstRun.dispose();

    final seen = <http.BaseRequest>[];
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen.add(request);
        return http.Response(_anyAnswer(), 200);
      }),
    );
    addTearDown(repository.dispose);
    final nextRun = _tablet(room: repository, ledger: ledger);
    addTearDown(nextRun.dispose);

    await nextRun.read(deviceLinkProvider.notifier).findTheTeam();
    await repository.fetchState('sessao-1');

    expect(seen.where((request) => request.url.path.endsWith('/credential')), isEmpty,
        reason: 'recolher de novo é pedir ao servidor uma credencial que ele já '
            'entregou, e a resposta permanente a isso é 403');
    expect(seen.last.headers['X-Device-Credential'], 'credencial-1');
  });

  test('a collection the network dropped is tried again, not punished', () async {
    final ledger = await _alreadyLinked();
    final room = FakeRoom()
      ..linkedTo = const TeamLink(projectId: 'equipe-terena')
      ..refuseCredentialWith = const RoomUnavailable('sem rede');
    final container = _tablet(room: room, ledger: ledger, linkPoll: _quickPoll);
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'a segunda tentativa de recolher',
      () => room.credentialsCollected.length > 1,
    );

    expect(container.read(deviceLinkProvider).code, isNull,
        reason: 'uma queda de rede lida como 403 apaga o vínculo de uma sala '
            'inteira por causa de um cabo');
    expect(container.read(deviceLinkProvider).team?.projectId, 'equipe-terena');
    final remembered = await ledger.read();
    expect(remembered.deviceId, 'aparelho-1');
    expect(remembered.team?.projectId, 'equipe-terena');
  });

  test('a device the room does not know leaves nothing behind on this tablet', () async {
    final ledger = await _alreadyLinked();
    final firstRoom = FakeRoom()
      ..linkedTo = const TeamLink(projectId: 'equipe-terena')
      ..refuseCredentialWith = const SessionGone();
    final firstRun = _tablet(room: firstRoom, ledger: ledger);
    await firstRun.read(deviceLinkProvider.notifier).findTheTeam();
    await waitFor(
      'um código novo aparecer',
      () => firstRun.read(deviceLinkProvider).code != null,
    );
    firstRun.dispose();

    final nextRun = _tablet(room: FakeRoom(), ledger: ledger);
    addTearDown(nextRun.dispose);
    await nextRun.read(deviceLinkProvider.notifier).findTheTeam();

    expect(nextRun.read(deviceLinkProvider).team, isNull,
        reason: 'a sala não conhece este aparelho; entrar como vinculado na abertura '
            'seguinte esconde do facilitador o código que ele precisaria anotar');
    await waitFor(
      'a abertura seguinte pedir um código',
      () => nextRun.read(deviceLinkProvider).code != null,
    );
    final remembered = await ledger.read();
    expect(remembered.team, isNull);
    expect(remembered.credential, isNull);
  });

  test('a credential that arrives after the tablet was put down is still kept', () async {
    final ledger = await _alreadyLinked();
    final arrives = Completer<void>();
    var asked = false;
    final firstRoom = RoomRepository(
      client: MockClient((request) async {
        if (!request.url.path.endsWith('/credential')) {
          return http.Response(_anyAnswer(), 200);
        }
        asked = true;
        await arrives.future;
        return http.Response(
          jsonEncode({'device_id': 'aparelho-1', 'credential': 'credencial-tardia'}),
          200,
        );
      }),
    );
    addTearDown(firstRoom.dispose);
    final firstRun = _tablet(room: firstRoom, ledger: ledger);
    unawaited(firstRun.read(deviceLinkProvider.notifier).findTheTeam());
    await waitFor('a coleta sair do tablet', () => asked);
    firstRun.dispose();
    arrives.complete();
    await waitFor(
      'a credencial tardia chegar ao disco — a única cópia já foi gasta no '
          'servidor, e jogá-la fora porque o tablet foi baixado transforma a '
          'abertura seguinte num 403 e num vínculo perdido',
      () async => (await ledger.read()).credential != null,
    );

    final seen = <http.BaseRequest>[];
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen.add(request);
        return http.Response(_anyAnswer(), 200);
      }),
    );
    addTearDown(repository.dispose);
    final nextRun = _tablet(room: repository, ledger: ledger);
    addTearDown(nextRun.dispose);

    await nextRun.read(deviceLinkProvider.notifier).findTheTeam();
    await repository.fetchState('sessao-1');

    expect(seen.where((request) => request.url.path.endsWith('/credential')), isEmpty,
        reason: 'a credencial já está em disco; recolher de novo pede ao servidor '
            'uma que ele já entregou');
    expect(seen.last.headers['X-Device-Credential'], 'credencial-tardia');
  });
}
