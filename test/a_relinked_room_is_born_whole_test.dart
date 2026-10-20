import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

const _linked = RememberedLink(
  deviceId: 'aparelho-1',
  team: TeamLink(projectId: 'equipe-1'),
  credential: 'credencial-1',
);

const _revoked = Refused(RefusalCode.deviceRevoked);

class _AnOutboxThatGaveUpOnATake extends FakeTakeQueue {
  _AnOutboxThatGaveUpOnATake({required super.room});

  @override
  Future<OutboxTally> tally({required String? sessionId}) async {
    final counted = await super.tally(sessionId: sessionId);
    return (
      stranded: true,
      unsentTakes: counted.unsentTakes,
      unsentChunks: counted.unsentChunks,
      unsentTakeScopes: counted.unsentTakeScopes,
      parts: counted.parts,
      due: counted.due,
    );
  }
}

SalaSessionState _read(ProviderContainer container) =>
    container.read(salaSessionProvider);

SalaSessionNotifier _room(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

Future<void> _enterP01(WidgetTester tester, ProviderContainer container) async {
  final p01 = _read(
    container,
  ).naRoda!.firstWhere((entry) => entry.pericope == 'P01');
  _room(container).openTheEntry(p01);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  expect(_read(container).station, isA<Canvas>());
}

Future<void> _theTeamIsRefused(
  WidgetTester tester,
  ProviderContainer container,
  SalaHarness harness,
) async {
  harness.room.failTurnsWith = const Refused('PIPELINE_REFUSED');
  _room(container).conversaTap();
  await tester.pump(const Duration(milliseconds: 100));
  _room(container).conversaTap();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  expect(_read(container).needsPerson, isTrue);
}

Future<void> _theDeskUnlinks(
  WidgetTester tester,
  ProviderContainer container,
  SalaHarness harness,
) async {
  harness.room.failWith = _revoked;
  await container.read(roomRepositoryProvider).fetchState('sessao-1');
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.byType(CodigoView), findsOneWidget);
}

Future<void> _theDeskLinksAgain(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room
    ..failWith = null
    ..failTurnsWith = null
    ..linkedTo = const TeamLink(projectId: 'equipe-2');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(CodigoView), findsNothing);
}

Future<void> _theRoomRefusesTheLineAgain(
  WidgetTester tester,
  ProviderContainer container,
  SalaHarness harness,
) async {
  harness.voice.roomFailsWith = const Refused('BAD_REQUEST');
  await _room(container).hearAgain();
  await tester.pump(const Duration(milliseconds: 100));
  harness.voice.roomFailsWith = null;
}

void main() {
  setUp(() => dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local'));

  testWidgets('a relinked room that needs a person calls one, though the room '
      'before the revocation had already called', (tester) async {
    final harness = SalaHarness(
      linkedAs: _linked,
      linkPoll: const Duration(milliseconds: 50),
    );
    final container = await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 300));
    await _enterP01(tester, container);
    await _theTeamIsRefused(tester, container, harness);
    expect(harness.room.personsAsked, 1);
    harness.room.theDeskAttended();

    await _theDeskUnlinks(tester, container, harness);
    await _theDeskLinksAgain(tester, harness);
    await _enterP01(tester, container);
    await _theTeamIsRefused(tester, container, harness);

    expect(
      harness.room.personsAsked,
      2,
      reason:
          'a chamada que pousou era da sala de antes do desvínculo; a sala '
          'nova nasce sem ter chamado ninguém (ADR 0070), e uma equipe parada '
          'sem chamada espera alguém que nunca foi avisado',
    );
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('a relinked room counts its refusals from none', (tester) async {
    final harness = SalaHarness(
      linkedAs: _linked,
      linkPoll: const Duration(milliseconds: 50),
    );
    final container = await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 300));
    await _enterP01(tester, container);
    for (
      var refusal = 1;
      refusal < FailurePolicy.refusalsBeforeAPerson;
      refusal++
    ) {
      await _theRoomRefusesTheLineAgain(tester, container, harness);
    }
    expect(_read(container).needsPerson, isFalse);

    await _theDeskUnlinks(tester, container, harness);
    await _theDeskLinksAgain(tester, harness);
    await _enterP01(tester, container);
    await _theRoomRefusesTheLineAgain(tester, container, harness);

    expect(
      _read(container).needsPerson,
      isFalse,
      reason:
          'as recusas contadas eram da sala de antes do desvínculo; a sala '
          'nova recebeu uma só, abaixo da escada',
    );
  });

  testWidgets('a relinked room says a recording is stranded again', (
    tester,
  ) async {
    final harness = SalaHarness(
      linkedAs: _linked,
      linkPoll: const Duration(milliseconds: 50),
      takesOverride: (room, _, _) => _AnOutboxThatGaveUpOnATake(room: room),
    );
    final container = await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 300));
    final stranded = strandedTakeAsset(testLanguage);
    await _room(container).refreshUnsent();
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.voice.assets.where((a) => a == stranded), hasLength(1));

    await _theDeskUnlinks(tester, container, harness);
    await _theDeskLinksAgain(tester, harness);
    await _room(container).refreshUnsent();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      harness.voice.assets.where((a) => a == stranded),
      hasLength(2),
      reason:
          'quem ouviu que uma gravação ficou presa foi a sala de antes do '
          'desvínculo; a sala nova nunca disse, e a equipe dela não sabe',
    );
  });

  testWidgets('a relinked tablet opens the room the way a first launch does', (
    tester,
  ) async {
    final currentSession = FakeCurrentSessionLedger();
    final harness = SalaHarness(
      linkedAs: _linked,
      linkPoll: const Duration(milliseconds: 50),
      currentSession: currentSession,
    );
    final container = await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EscolhaView), findsOneWidget);

    await _theDeskUnlinks(tester, container, harness);
    currentSession.held = const CurrentSession(
      sessionId: 'sessao-7',
      book: 'Ruth',
      pericope: 'P02',
      language: testLanguage,
    );
    await _theDeskLinksAgain(tester, harness);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _read(container).station,
      isA<Canvas>(),
      reason:
          'revinculado, o tablet abre a sala como um primeiro lançamento '
          '(ADR 0070): pousa na Sessão atual que a sala ainda guarda (ADR 0064)',
    );
    expect(_read(container).sessionId, 'sessao-7');
  });
}
