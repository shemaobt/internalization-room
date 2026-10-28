import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _gravacao = 'gravacao-1';
const _aPart = Duration(seconds: 30);
const _watchBeat = Duration(milliseconds: 150);
final _theRoomsRecording = Uint8List.fromList([7, 7, 7, 7]);

const _checked = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: _gravacao,
      startsMs: 0,
      endsMs: 12000,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: _gravacao,
      startsMs: 12000,
      endsMs: 30000,
    ),
  ],
  checked: true,
);

ApprovedDraft _approvedAs(int version) => ApprovedDraft(version: version);

typedef _Room = ({SalaHarness harness, ProviderContainer container});

/// A team whose passage the room holds with a checked telling-back over its one part,
/// under [approved] when it is set.
SalaHarness _aRoomHolding({
  ApprovedDraft? approved,
  String lingua = testLanguage,
  bool watching = false,
}) {
  final harness =
      SalaHarness(
          lingua: lingua,
          settleDelay: _watchBeat,
          watchesWithoutAHalt: watching,
        )
        ..playback.length = _aPart
        ..playback.measured = _aPart;
  harness.room
    ..approvedDraft = approved
    ..retroSoFar = _checked
    ..takes.add(
      const TakeView(
        takeId: _gravacao,
        kind: 'ensaio',
        scope: 'parte-1',
        ordinal: 1,
      ),
    )
    ..takeAudio[_gravacao] = _theRoomsRecording;
  return harness;
}

/// A resume point on [stage] naming the rehearsal, still on this tablet.
void _aRowOn(SalaHarness harness, SalaStage stage) {
  final home = Directory.systemTemp.createTempSync('sala-rascunho');
  addTearDown(() => home.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: stage,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File('${home.path}/p1.m4a')..writeAsBytesSync([1])).path,
        takeId: _gravacao,
      ),
    ],
  );
}

Future<_Room> _enter(
  WidgetTester tester,
  SalaHarness harness, {
  Future<void> Function(SalaSessionNotifier notifier)? by,
}) async {
  late ProviderContainer container;
  await tester.runAsync(() async {
    container = harness.container();
    final notifier = container.read(salaSessionProvider.notifier);
    if (by != null) {
      await by(notifier);
    } else {
      await notifier.abrirEscolha();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  addTearDown(() => closeTheRoom(container));
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return (harness: harness, container: container);
}

SalaSessionState _state(_Room room) => room.container.read(salaSessionProvider);

Finder _theBadge(int version, [String language = testLanguage]) =>
    find.text(retroLabelFor('approvedDraft', language, n: version));

int _opensAsked(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'openSession').length;

void _landsOnTheConversation(_Room room) {
  final state = _state(room);
  expect(
    state.station,
    isA<Canvas>(),
    reason: 'a passagem aprovada reabria na retrotradução, não na conversa',
  );
  expect(state.voice, VoiceState.invite);
  expect(byLabel(roomLabelFor('hearAgain', testLanguage)), findsOneWidget);
  expect(
    _opensAsked(room.harness),
    0,
    reason: 'a passagem aprovada não é uma conversa a abrir',
  );
  expect(room.harness.voice.played, isEmpty);
}

void main() {
  testWidgets(
    'choosing a passage the room says is approved lands on its conversation at '
    'rest with «Ouvir de novo», never on its translation',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.nextCoverage = coverage(engaged: 9);

      final room = await _enter(tester, harness);

      _landsOnTheConversation(room);
      expect(_state(room).coverage.beadsFilled, 9);
    },
  );

  group('a Back-translation row with no parts, entered again', () {
    void aPartlessRow(SalaHarness harness) {
      harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = const ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
      );
      harness.room.openedSessions.add('sessao-antiga');
    }

    testWidgets(
      'with a re-told frase still in the Outbox gets its parts from the room, '
      'and no badge',
      (tester) async {
        final harness = _aRoomHolding(approved: _approvedAs(1));
        aPartlessRow(harness);
        await tester.runAsync(() async {
          final home = Directory.systemTemp.createTempSync(
            'sala-frase-na-fila',
          );
          addTearDown(() => home.deleteSync(recursive: true));
          await harness.takes.enqueue(
            File('${home.path}/frase-1.m4a')..writeAsBytesSync([5, 5]),
            sessionId: 'sessao-antiga',
            kind: sentenceKind,
            scope: '1',
          );
        });

        final room = await _enter(tester, harness);

        expect(_state(room).stage, SalaStage.retro);
        expect(_state(room).partes, hasLength(1));
        expect(_theBadge(1), findsNothing);
      },
    );

    testWidgets(
      'lands on its conversation with the coverage and the moment of that read',
      (tester) async {
        final harness = _aRoomHolding(approved: _approvedAs(1))
          ..room.nextCoverage = coverage(engaged: 3)
          ..room.nextMoment = const Moment(
            at: MomentAt.articulation,
            part: 2,
            parts: 3,
          );
        aPartlessRow(harness);

        final room = await _enter(tester, harness);

        _landsOnTheConversation(room);
        expect(_state(room).coverage.engaged, 3);
        expect(_state(room).moment?.at, MomentAt.articulation);
        expect(_state(room).moment?.part, 2);
      },
    );

    testWidgets(
      'decides and lands on its conversation from one read of the session',
      (tester) async {
        final harness = _aRoomHolding(approved: _approvedAs(1));
        aPartlessRow(harness);

        final room = await _enter(tester, harness);

        _landsOnTheConversation(room);
        expect(
          harness.room.calls.where((call) => call == 'fetchState'),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'then the dot opens the recording home with the room\'s part laid in '
      'under it, not a home with no part',
      (tester) async {
        final harness = _aRoomHolding(approved: _approvedAs(1));
        aPartlessRow(harness);
        final room = await _enter(tester, harness);

        await tester.runAsync(() async {
          room.container
              .read(salaSessionProvider.notifier)
              .openTheEnsaioFinal();
          await Future<void>.delayed(const Duration(seconds: 1));
        });
        await tester.pump(const Duration(milliseconds: 100));

        expect(_state(room).stage, SalaStage.ensaio);
        expect(_state(room).partes.map((parte) => parte.takeId), [_gravacao]);
        expect(
          File(_state(room).partes.single.path).readAsBytesSync(),
          _theRoomsRecording,
          reason: 'a casa abria sem a parte que a sala guarda',
        );
      },
    );
  });

  testWidgets(
    'a forced approval over a telling-back never checked, re-entered, lands '
    'on its conversation as any approval does',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.retroSoFar = BackTranslationProgress(
          segments: _checked.segments,
        );

      final room = await _enter(tester, harness);

      _landsOnTheConversation(room);
      expect(harness.playback.played, isEmpty);
    },
  );

  testWidgets(
    'an approved passage the room never opened lands on its conversation too, '
    'and asks no opening',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = false;

      final room = await _enter(tester, harness);

      _landsOnTheConversation(room);
    },
  );

  group(
    'from that conversation the dot leads to the recording home, with the badge '
    'naming the version the room read',
    () {
      for (final (why, lingua, badge, check) in [
        (
          'in Portuguese',
          'pt',
          '✓ aprovado como rascunho final (v3)',
          'Checagem externa',
        ),
        (
          'in English',
          'en',
          '✓ approved as the final draft (v3)',
          'External check',
        ),
      ]) {
        testWidgets(why, (tester) async {
          final room = await _enter(
            tester,
            _aRoomHolding(approved: _approvedAs(3), lingua: lingua)
              ..room.createdOpened = true,
          );

          await tester.runAsync(() async {
            room.container
                .read(salaSessionProvider.notifier)
                .openTheEnsaioFinal();
            await Future<void>.delayed(const Duration(seconds: 1));
          });
          await tester.pump(const Duration(milliseconds: 100));

          expect(_state(room).station, const Ensaio());
          expect(find.text(badge), findsOneWidget);
          expect(byLabel(check), findsOneWidget);
        });
      }
    },
  );

  testWidgets(
    'a relaunch onto an approved current session lands on its conversation',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1));
      (harness.currentSession as FakeCurrentSessionLedger).held =
          const CurrentSession(
            sessionId: 'sessao-aprovada',
            book: 'Ruth',
            pericope: 'P01',
            language: testLanguage,
          );

      final room = await _enter(
        tester,
        harness,
        by: (notifier) => notifier.openTheRoom(),
      );

      _landsOnTheConversation(room);
      expect(_state(room).sessionId, 'sessao-aprovada');
    },
  );

  testWidgets(
    'after a relaunch onto an approved session the dot leads to the recording '
    'home, with the badge naming the version the room read',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(2));
      (harness.currentSession as FakeCurrentSessionLedger).held =
          const CurrentSession(
            sessionId: 'sessao-aprovada',
            book: 'Ruth',
            pericope: 'P01',
            language: testLanguage,
          );
      final room = await _enter(
        tester,
        harness,
        by: (notifier) => notifier.openTheRoom(),
      );

      await tester.runAsync(() async {
        room.container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(_state(room).station, const Ensaio());
      expect(
        _theBadge(2),
        findsOneWidget,
        reason: 'a casa depois do relançamento perdia o selo da versão',
      );
    },
  );

  group(
    'a tablet still holding a resume point for a draft another tablet approved '
    'lands on its conversation, and the point stands there after',
    () {
      for (final stage in [
        SalaStage.ensaio,
        SalaStage.retro,
        SalaStage.conversa,
      ]) {
        testWidgets('from a resume point on ${stage.name}', (tester) async {
          final harness = _aRoomHolding(approved: _approvedAs(1));
          _aRowOn(harness, stage);
          harness.room.openedSessions.add('sessao-antiga');

          final room = await _enter(tester, harness);

          _landsOnTheConversation(room);
          expect(
            harness.emAberto.rows['Ruth/P01/${harness.lingua}']?.stage,
            SalaStage.conversa,
          );
        });
      }
    },
  );

  testWidgets(
    'an approved passage relaunched on a Rehearsal row goes straight to its '
    'conversation, never through the recording home',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1));
      _aRowOn(harness, SalaStage.ensaio);
      harness.room.openedSessions.add('sessao-antiga');
      (harness.currentSession as FakeCurrentSessionLedger).held =
          const CurrentSession(
            sessionId: 'sessao-antiga',
            book: 'Ruth',
            pericope: 'P01',
            language: testLanguage,
          );
      final stood = <SalaStage>[];
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = harness.container();
        container.listen(
          salaSessionProvider,
          (_, next) => stood.add(next.stage),
        );
        await container.read(salaSessionProvider.notifier).openTheRoom();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      addTearDown(() => closeTheRoom(container));

      expect(container.read(salaSessionProvider).station, isA<Canvas>());
      expect(
        stood,
        isNot(contains(SalaStage.ensaio)),
        reason:
            'a casa das gravações aparecia por uma leitura antes da conversa',
      );
    },
  );

  group('a take recorded over by a newer recording, refused for good', () {
    Future<_Room> enterOver(WidgetTester tester, String refusal) async {
      final harness = _aRoomHolding(approved: _approvedAs(1));
      harness.room.takes
        ..clear()
        ..add(
          const TakeView(
            takeId: _gravacao,
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
            pass: 2,
          ),
        );
      final home = Directory.systemTemp.createTempSync('sala-recoberta');
      addTearDown(() => home.deleteSync(recursive: true));
      harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: [
          KeptTake(
            scopeId: KeptScope.parte(1),
            path: (File('${home.path}/p1b.m4a')..writeAsBytesSync([2])).path,
            takeId: _gravacao,
            pass: 2,
          ),
        ],
      );
      harness.room.openedSessions.add('sessao-antiga');
      final guardadas = Directory('${harness.takesHome.path}/guardadas')
        ..createSync(recursive: true);
      final recoberta = File('${guardadas.path}/ensaio-p1a.m4a')
        ..writeAsBytesSync([1]);
      File('${guardadas.path}/fila.json').writeAsStringSync(
        jsonEncode([
          PendingTake(
            id: 'r1',
            path: recoberta.path,
            sessionId: 'sessao-antiga',
            kind: 'ensaio',
            scope: 'parte-1',
            passNumber: 1,
            chunkIndex: 1,
            attempts: takeUploadAttempts,
            refusal: refusal,
          ).toJson(),
        ]),
      );
      return _enter(tester, harness);
    }

    testWidgets(
      'with a code the room gave never keeps an approved passage off its '
      'conversation',
      (tester) async {
        final room = await enterOver(tester, 'UNKNOWN_REFERENCE');

        _landsOnTheConversation(room);
      },
    );

    testWidgets(
      'with no code still waits for the team\'s tap, and the passage lands '
      'where it stood',
      (tester) async {
        final room = await enterOver(tester, RefusalCode.unnamed(500));

        expect(
          _state(room).stage,
          SalaStage.retro,
          reason: 'uma gravação que o toque ainda envia mudava o rascunho',
        );
        expect(
          _theBadge(1),
          findsOneWidget,
          reason: 'a retrotradução sobre o rascunho aprovado perdia o selo',
        );
      },
    );
  });

  group(
    'a tablet whose Outbox still holds something of the session that changes the '
    'draft lands where it stood, never on the approved draft',
    () {
      for (final (what, kind, scope) in [
        ('a take', 'ensaio', 'parte-1'),
        ('a re-told frase', sentenceKind, '1'),
      ]) {
        testWidgets(what, (tester) async {
          final harness = _aRoomHolding(approved: _approvedAs(1))
            ..room.takeLandsAfter = const Duration(minutes: 1);
          _aRowOn(harness, SalaStage.ensaio);
          harness.room.openedSessions.add('sessao-antiga');
          await tester.runAsync(() async {
            final home = Directory.systemTemp.createTempSync('sala-no-outbox');
            addTearDown(() => home.deleteSync(recursive: true));
            await harness.takes.enqueue(
              File('${home.path}/de-novo.m4a')..writeAsBytesSync([5, 5]),
              sessionId: 'sessao-antiga',
              kind: kind,
              scope: scope,
              passNumber: 2,
            );
          });

          final room = await _enter(tester, harness);

          expect(_state(room).stage, SalaStage.ensaio);
          expect(_theBadge(1), findsNothing);
        });
      }
    },
  );

  testWidgets(
    'a re-told frase still in the Outbox keeps the badge off the checked '
    'translation, with the approve button',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1));
      _aRowOn(harness, SalaStage.retro);
      harness.room.openedSessions.add('sessao-antiga');
      await tester.runAsync(() async {
        final home = Directory.systemTemp.createTempSync('sala-frase-na-fila');
        addTearDown(() => home.deleteSync(recursive: true));
        await harness.takes.enqueue(
          File('${home.path}/frase-1.m4a')..writeAsBytesSync([5, 5]),
          sessionId: 'sessao-antiga',
          kind: sentenceKind,
          scope: '1',
        );
      });

      final room = await _enter(tester, harness);

      expect(_state(room).stage, SalaStage.retro);
      expect(_theBadge(1), findsNothing);
      expect(byLabel(retroLabelFor('approve', testLanguage)), findsOneWidget);
    },
  );

  group('a passage with no approval lands as it always did', () {
    testWidgets('a passage with takes lands where it stood', (tester) async {
      final harness = _aRoomHolding();
      _aRowOn(harness, SalaStage.ensaio);
      harness.room.openedSessions.add('sessao-antiga');

      final room = await _enter(tester, harness);

      expect(_state(room).stage, SalaStage.ensaio);
      expect(_theBadge(1), findsNothing);
    });

    testWidgets('a fresh passage never opened asks its Opening', (
      tester,
    ) async {
      final harness = _aRoomHolding()
        ..room.retroSoFar = null
        ..room.createdOpened = false;

      final room = await _enter(tester, harness);

      expect(_opensAsked(room.harness), 1);
      expect(_state(room).stage, SalaStage.conversa);
    });
  });
}
