import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
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

void _landsOnTheApprovedDraft(_Room room, {int version = 1}) {
  final state = _state(room);
  expect(state.stage, SalaStage.retro);
  expect(state.btPhase, BtPhase.conferida);
  expect(_theBadge(version), findsOneWidget);
  expect(
    _opensAsked(room.harness),
    0,
    reason: 'a passagem aprovada não é uma conversa a abrir',
  );
}

void main() {
  testWidgets(
    're-entering a passage the room says is approved lands on its translation '
    'with «✓ aprovado como rascunho final (v1)»',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.nextCoverage = coverage(engaged: 9);

      final room = await _enter(tester, harness);

      _landsOnTheApprovedDraft(room);
      expect(_state(room).btTrechos, hasLength(2));
      expect(_state(room).coverage.beadsFilled, 9);
      expect(harness.voice.played, isNot(contains(turnoUrl)));
    },
  );

  testWidgets(
    'a Watch beat read while the parts come down leaves the badge drawn',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1), watching: true)
        ..room.createdOpened = true;
      int reads() => harness.room.calls.where((c) => c == 'fetchState').length;

      await _enter(
        tester,
        harness,
        by: (notifier) async {
          await notifier.abrirEscolha();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          harness.room.holdNextClip();
          final entering = notifier.goConversa(book: 'Ruth', pericope: 'P01');
          final before = reads();
          await waitFor(
            'a Watch beat while the part is still coming down',
            () => reads() > before,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          for (var beat = 0; beat < 40; beat++) {
            harness.room.holdTheNextRead();
          }
          harness.room.finishHeldClip();
          await entering;
        },
      );

      expect(_theBadge(1), findsOneWidget);
      expect(byLabel(retroLabelFor('approve', testLanguage)), findsNothing);
    },
  );

  testWidgets(
    'a Watch beat that reads the approval gone while the parts come down is '
    'not undone by the older read the landing came with',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1), watching: true)
        ..room.createdOpened = true;
      int reads() => harness.room.calls.where((c) => c == 'fetchState').length;

      await _enter(
        tester,
        harness,
        by: (notifier) async {
          await notifier.abrirEscolha();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          harness.room.holdNextClip();
          final entering = notifier.goConversa(book: 'Ruth', pericope: 'P01');
          final before = reads();
          await waitFor(
            'a first Watch beat while the part is still coming down',
            () => reads() > before,
          );
          harness.room.approvedDraft = null;
          final gone = reads();
          await waitFor(
            'a beat that reads the approval gone',
            () => reads() > gone,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          for (var beat = 0; beat < 40; beat++) {
            harness.room.holdTheNextRead();
          }
          harness.room.finishHeldClip();
          await entering;
        },
      );

      expect(_theBadge(1), findsNothing);
      expect(byLabel(retroLabelFor('approve', testLanguage)), findsOneWidget);
    },
  );

  testWidgets(
    'keeping the earlier translation of a frase brings the badge back at once',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true;
      final room = await _enter(tester, harness);

      await tester.runAsync(() async {
        final notifier = room.container.read(salaSessionProvider.notifier)
          ..traduzirAFraseDeNovo(0);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        notifier.manterATraducaoDeAntes();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(_theBadge(1), findsOneWidget);
      expect(byLabel(retroLabelFor('approve', testLanguage)), findsNothing);
    },
  );

  testWidgets(
    'a passage whose approved landing could not get its parts gets them on the '
    'next entry, after the approval is gone',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.failTakesWith = const NetworkFailed('sem rede');
      final room = await _enter(tester, harness);
      _landsOnTheApprovedDraft(room);

      harness.room
        ..approvedDraft = null
        ..failTakesWith = null;
      await tester.runAsync(() async {
        final notifier = room.container.read(salaSessionProvider.notifier)
          ..leaveThePassage();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await notifier.abrirEscolha();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await notifier.goConversa(book: 'Ruth', pericope: 'P01');
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(_state(room).stage, SalaStage.retro);
      expect(_state(room).partes, isNotEmpty);
    },
  );

  group(
    'an approved draft whose parts the room cannot hand over lands on the draft, '
    'silent, on every entry',
    () {
      for (final (why, failure) in [
        ('the network', const NetworkFailed('sem rede') as RoomFailure),
        ('a lasting refusal', const Refused(RefusalCode.unreadable)),
      ]) {
        testWidgets(why, (tester) async {
          final harness = _aRoomHolding(approved: _approvedAs(1))
            ..room.createdOpened = true
            ..room.failTakesWith = failure;
          final room = await _enter(tester, harness);
          _landsOnTheApprovedDraft(room);

          await tester.runAsync(() async {
            final notifier = room.container.read(salaSessionProvider.notifier)
              ..leaveThePassage();
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await notifier.abrirEscolha();
            await Future<void>.delayed(const Duration(milliseconds: 200));
            await notifier.goConversa(book: 'Ruth', pericope: 'P01');
            await Future<void>.delayed(const Duration(seconds: 1));
          });
          await tester.pump(const Duration(milliseconds: 100));

          _landsOnTheApprovedDraft(room);
          expect(_state(room).needsPerson, isFalse);
          expect(harness.room.personsAsked, 0);
        });
      }
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
      'decides and lands on its approved draft from one read of the session',
      (tester) async {
        final harness = _aRoomHolding(approved: _approvedAs(1));
        aPartlessRow(harness);

        final room = await _enter(tester, harness);

        _landsOnTheApprovedDraft(room);
        expect(
          harness.room.calls.where((call) => call == 'fetchState'),
          hasLength(1),
        );
      },
    );
  });

  testWidgets('tapping a frase of the approved draft plays its part', (
    tester,
  ) async {
    final harness = _aRoomHolding(approved: _approvedAs(1))
      ..room.createdOpened = true;
    final room = await _enter(tester, harness);

    await tester.runAsync(() async {
      room.container.read(salaSessionProvider.notifier).ouvirOTrechoContado(1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    expect(harness.playback.played, isNotEmpty);
    expect(
      File(harness.playback.played.last).readAsBytesSync(),
      _theRoomsRecording,
      reason: 'a frase toca a parte que a sala guarda, baixada para o tablet',
    );
  });

  testWidgets(
    'an approved draft whose recording the room cannot hand over still lands '
    'on the draft, with no sign and listening dimmed',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.failTakesWith = const NetworkFailed('sem rede');

      final room = await _enter(tester, harness);

      _landsOnTheApprovedDraft(room);
      final state = _state(room);
      expect(state.needsPerson, isFalse);
      expect(state.unreachable, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(
        tester
            .widget<RoundActionButton>(
              find.ancestor(
                of: byLabel(
                  retroLabelFor('listenToTheRecording', testLanguage),
                ),
                matching: find.byType(RoundActionButton),
              ),
            )
            .mood,
        ButtonMood.dimmed,
      );
    },
  );

  testWidgets(
    'a forced approval over a telling-back never checked, re-entered, lands '
    'checked with the badge',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.retroSoFar = BackTranslationProgress(
          segments: _checked.segments,
        );

      final room = await _enter(tester, harness);

      _landsOnTheApprovedDraft(room);
      expect(harness.playback.played, isEmpty);
    },
  );

  testWidgets(
    'an approved passage the room never opened still lands on its draft, '
    'never on the Conversation at zero',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = false;

      final room = await _enter(tester, harness);

      _landsOnTheApprovedDraft(room);
    },
  );

  group('the badge names the version the room read', () {
    testWidgets('in Portuguese', (tester) async {
      await _enter(
        tester,
        _aRoomHolding(approved: _approvedAs(3))..room.createdOpened = true,
      );

      expect(find.text('✓ aprovado como rascunho final (v3)'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      final room = await _enter(
        tester,
        _aRoomHolding(approved: _approvedAs(3), lingua: 'en')
          ..room.createdOpened = true,
      );

      expect(room.harness.room.languagesSent.last, 'en');
      expect(find.text('✓ approved as the final draft (v3)'), findsOneWidget);
    });
  });

  testWidgets(
    'a relaunch onto an approved current session lands on its draft',
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

      _landsOnTheApprovedDraft(room);
      expect(_state(room).sessionId, 'sessao-aprovada');
    },
  );

  group(
    'a tablet still holding a resume point for a draft another tablet approved '
    'lands on the approved draft',
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

          _landsOnTheApprovedDraft(room);
        });
      }
    },
  );

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

  testWidgets(
    'the approved draft shows no warning mark even while the room still holds a '
    'warning',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning;

      final room = await _enter(tester, harness);

      _landsOnTheApprovedDraft(room);
      expect(byLabel(warningNoticeLabelFor(testLanguage)), findsNothing);
    },
  );

  testWidgets(
    'translating a frase of the approved draft again leaves the approved draft, '
    'and the warning mark stands again',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1))
        ..room.createdOpened = true
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning;
      final room = await _enter(tester, harness);
      _landsOnTheApprovedDraft(room);

      await tester.runAsync(() async {
        room.container
            .read(salaSessionProvider.notifier)
            .traduzirAFraseDeNovo(0);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(_theBadge(1), findsNothing);
      expect(byLabel(warningNoticeLabelFor(testLanguage)), findsOneWidget);
    },
  );

  testWidgets(
    'the approve button is not offered on an approved draft; the listen button is',
    (tester) async {
      await _enter(
        tester,
        _aRoomHolding(approved: _approvedAs(1))..room.createdOpened = true,
      );

      expect(byLabel(retroLabelFor('approve', testLanguage)), findsNothing);
      expect(
        byLabel(retroLabelFor('listenToTheRecording', testLanguage)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a session read that says the draft is no longer approved takes the badge away',
    (tester) async {
      final harness = _aRoomHolding(approved: _approvedAs(1), watching: true)
        ..room.createdOpened = true;
      final room = await _enter(tester, harness);
      _landsOnTheApprovedDraft(room);

      harness.room.approvedDraft = null;
      final reads = harness.room.calls.where((c) => c == 'fetchState').length;
      await tester.runAsync(
        () => waitFor(
          'a Watch beat to read the session again',
          () =>
              harness.room.calls.where((c) => c == 'fetchState').length > reads,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));

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
