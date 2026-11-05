import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'support/temp.dart';

const _passage = 'Genesis/P01/pt';

typedef _Tablet = ({SalaHarness harness, ProviderContainer container});

Future<_Tablet> _aTablet(RememberedLink link) async {
  final harness = SalaHarness(
    linkedAs: link,
    linkPoll: const Duration(milliseconds: 20),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(deviceLinkProvider.notifier).findTheTeam();
  return (harness: harness, container: container);
}

Future<_Tablet> _linkedTo(String team) => _aTablet(
  RememberedLink(
    deviceId: 'aparelho-$team',
    team: TeamLink(projectId: team),
    credential: 'credencial-$team',
  ),
);

Future<File> _aTakeRecordedOffline(_Tablet tablet, String sessionId) async {
  tablet.harness.room.reachable = false;
  final source = File('${tablet.harness.recorder.home.path}/parte1.m4a')
    ..writeAsBytesSync([1, 2, 3]);
  final row = await tablet.harness.takes.enqueue(
    source,
    sessionId: sessionId,
    passage: _passage,
    kind: partTakeKind,
    scope: 'parte-1',
    passNumber: 1,
    chunkIndex: 1,
  );
  return File(row.path);
}

Future<void> _theDeskUnlinks(_Tablet tablet) async {
  final room = tablet.harness.room
    ..reachable = true
    ..linkedTo = null
    ..failWith = const Refused(RefusalCode.deviceRevoked);
  await tablet.container.read(roomRepositoryProvider).fetchState('sessao-1');
  await waitFor(
    'the revoked link to be forgotten and a fresh code to show',
    () =>
        tablet.harness.vinculo.remembered.credential == null &&
        tablet.container.read(deviceLinkProvider).code != null,
  );
  room.failWith = null;
  await settle();
}

Future<void> _theDeskLinks(
  _Tablet tablet,
  String team, {
  Set<String> foreignSessions = const {},
}) async {
  final room = tablet.harness.room;
  room
    ..forgottenSessions.clear()
    ..forgottenSessions.addAll(foreignSessions)
    ..credential = 'credencial-$team-${room.credentialsCollected.length}'
    ..linkedTo = TeamLink(projectId: team);
  await waitFor(
    'the tablet to be linked to $team',
    () => tablet.container.read(deviceLinkProvider).linked,
  );
  await tablet.harness.takes.flush();
  await settle();
}

void _anOlderAppWroteARow(SalaHarness harness, String sessionId) {
  final dir = Directory('${harness.takesHome.path}/guardadas')
    ..createSync(recursive: true);
  File(
    '${dir.path}/ensaio-parte1-1700000000000000-0.m4a',
  ).writeAsBytesSync([4, 5, 6]);
  File('${dir.path}/fila.json').writeAsStringSync(
    '[{"id":"antiga","name":"ensaio-parte1-1700000000000000-0.m4a","session_id":"$sessionId",'
    '"passage":"$_passage","kind":"$partTakeKind","scope":"parte-1",'
    '"pass_number":1,"chunk_index":1,"stored":false,"lost":false,'
    '"attempts":0,"waits":0,"last_try":null}]',
  );
}

Future<int> _onTheHomeOf(_Tablet tablet, String sessionId) async =>
    (await tablet.harness.takes.tally(
      sessionId: sessionId,
      passage: _passage,
    )).unsentTakes;

void main() {
  setUp(() => dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local'));

  test('a take of the team before a re-link is not sent, not on the new '
      "team's home, and still on the tablet", () async {
    final tablet = await _linkedTo('equipe-1');
    final copy = await _aTakeRecordedOffline(tablet, 'sessao-1');

    await _theDeskUnlinks(tablet);
    final sentBefore = tablet.harness.room.takeSessions.length;
    await _theDeskLinks(tablet, 'equipe-2', foreignSessions: {'sessao-1'});

    expect(tablet.harness.room.takeSessions.skip(sentBefore), isEmpty);
    expect(await _onTheHomeOf(tablet, 'sessao-9'), 0);
    expect(copy.existsSync(), isTrue);
  });

  test("a 404 on the old team's session keeps its row, and linked back to its "
      'team the take goes up to its own session', () async {
    final tablet = await _linkedTo('equipe-1');
    await _aTakeRecordedOffline(tablet, 'sessao-1');
    await _theDeskUnlinks(tablet);
    await _theDeskLinks(tablet, 'equipe-2', foreignSessions: {'sessao-1'});
    await tablet.harness.takes.letGoOfTheSession('sessao-1', passage: _passage);
    expect(await _onTheHomeOf(tablet, 'sessao-9'), 0);
    await _theDeskUnlinks(tablet);
    final sentBefore = tablet.harness.room.takeSessions.length;

    await _theDeskLinks(tablet, 'equipe-1');

    expect(tablet.harness.room.takeSessions.skip(sentBefore), ['sessao-1']);
    expect(await tablet.harness.takes.entries(), isEmpty);
  });

  test(
    'a re-link to the same team sends its take up on the new link',
    () async {
      final tablet = await _linkedTo('equipe-1');
      await _aTakeRecordedOffline(tablet, 'sessao-1');
      await _theDeskUnlinks(tablet);
      final sentBefore = tablet.harness.room.takeSessions.length;

      await _theDeskLinks(tablet, 'equipe-1');

      expect(tablet.harness.room.takeSessions.skip(sentBefore), ['sessao-1']);
      expect(await tablet.harness.takes.entries(), isEmpty);
    },
  );

  test("the new team's home of the same part lists none of the old team's "
      'takes', () async {
    final tablet = await _linkedTo('equipe-1');
    SalaSessionNotifier sala() =>
        tablet.container.read(salaSessionProvider.notifier);
    SalaSessionState estado() => tablet.container.read(salaSessionProvider);
    Future<void> aPartIsKept() async {
      await sala().goConversa(book: 'Ruth');
      await settle();
      sala()
        ..goEnsaio()
        ..gravarACena(1)
        ..gravarACena(1);
      await waitFor('a take', () => estado().ensaio == EnsaioStatus.recorded);
      sala().takeKeep();
      await settle();
    }

    tablet.harness.room.unreachableTake = 'ensaio/parte-1';
    await aPartIsKept();
    final theirs = estado().sessionId!;
    await _theDeskUnlinks(tablet);
    await _theDeskLinks(tablet, 'equipe-2', foreignSessions: {theirs});
    await tablet.harness.takes.letGoOfTheSession(theirs);
    tablet.harness.room.unreachableTake = null;
    await aPartIsKept();

    expect(estado().sessionId, isNot(theirs));
    expect(estado().unsentParts, isEmpty);
    expect(estado().unsentTakes, 0);
  });

  test("a 404 on the old team's session forgets none of its Resume point, and "
      'linked back to its team the passage resumes where it stood', () async {
    late ProviderContainer container;
    final home = aTempDir('sala-em-curso-relink');
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => home,
      team: () => container.read(deviceLinkProvider).team?.projectId,
    );
    final harness = SalaHarness(
      linkedAs: const RememberedLink(
        deviceId: 'aparelho-1',
        team: TeamLink(projectId: 'equipe-1'),
        credential: 'credencial-1',
      ),
      linkPoll: const Duration(milliseconds: 20),
      emAbertoNoDisco: ledger,
    );
    container = harness.container();
    addTearDown(container.dispose);
    await container.read(deviceLinkProvider.notifier).findTheTeam();
    final tablet = (harness: harness, container: container);
    await ledger.remember(
      'Ruth',
      'P01',
      'pt',
      const ResumePoint(
        sessionId: 'sessao-da-equipe-1',
        stage: SalaStage.ensaio,
      ),
    );
    final sala = container.read(salaSessionProvider.notifier);

    await _theDeskUnlinks(tablet);
    await _theDeskLinks(
      tablet,
      'equipe-2',
      foreignSessions: {'sessao-da-equipe-1'},
    );
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'the new team to open the passage',
      () => container.read(salaSessionProvider).sessionId != null,
    );

    expect(
      container.read(salaSessionProvider).sessionId,
      isNot('sessao-da-equipe-1'),
    );

    await sala.abrirEscolha();
    await settle();
    await _theDeskUnlinks(tablet);
    await _theDeskLinks(tablet, 'equipe-1');
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'the first team to resume its passage',
      () =>
          container.read(salaSessionProvider).sessionId == 'sessao-da-equipe-1',
    );
  });

  test(
    'a revocation that is not a re-link leaves the take on the tablet',
    () async {
      final tablet = await _linkedTo('equipe-1');
      final copy = await _aTakeRecordedOffline(tablet, 'sessao-1');

      await _theDeskUnlinks(tablet);

      expect(copy.existsSync(), isTrue);
    },
  );

  test(
    'a row an older app wrote belongs to the team the tablet leaves',
    () async {
      final harness = SalaHarness(
        linkedAs: const RememberedLink(
          deviceId: 'aparelho-1',
          team: TeamLink(projectId: 'equipe-1'),
          credential: 'credencial-1',
        ),
        linkPoll: const Duration(milliseconds: 20),
      );
      _anOlderAppWroteARow(harness, 'sessao-1');
      harness.room.reachable = false;
      final container = harness.container();
      addTearDown(container.dispose);
      await container.read(deviceLinkProvider.notifier).findTheTeam();
      final tablet = (harness: harness, container: container);

      await _theDeskUnlinks(tablet);
      final sentBefore = harness.room.takeSessions.length;
      await _theDeskLinks(tablet, 'equipe-2', foreignSessions: {'sessao-1'});
      expect(harness.room.takeSessions.skip(sentBefore), isEmpty);
      expect(await _onTheHomeOf(tablet, 'sessao-9'), 0);

      await _theDeskUnlinks(tablet);
      await _theDeskLinks(tablet, 'equipe-1');
      harness.takes.tapped('antiga');
      await harness.takes.flush();
      expect(harness.room.takeSessions.skip(sentBefore), ['sessao-1']);
    },
  );

  test('a row an older app wrote, left when the link could not be read, is '
      'never sent, never listed and never deleted', () async {
    final harness = SalaHarness(
      linkedAs: const RememberedLink(credential: 'credencial-1'),
      linkPoll: const Duration(milliseconds: 20),
    );
    _anOlderAppWroteARow(harness, 'sessao-1');
    harness.room.reachable = false;
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(deviceLinkProvider.notifier).findTheTeam();
    final tablet = (harness: harness, container: container);
    await _theDeskUnlinks(tablet);
    final sentBefore = harness.room.takeSessions.length;

    await _theDeskLinks(tablet, 'equipe-1');

    expect(harness.room.takeSessions.skip(sentBefore), isEmpty);
    expect(await _onTheHomeOf(tablet, 'sessao-1'), 0);
    expect(
      File(
        '${harness.takesHome.path}/guardadas/'
        'ensaio-parte1-1700000000000000-0.m4a',
      ).existsSync(),
      isTrue,
    );
  });
}
