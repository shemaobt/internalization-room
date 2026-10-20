import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _aPart = Duration(seconds: 30);

/// A tablet reopened into the Back-translation of a one-part rehearsal, told back as far
/// as [toldUpTo], with the player walking the part the way a real one does.
Future<(SalaHarness, ProviderContainer)> _reopenedInto(
  WidgetTester tester, {
  required int toldUpTo,
}) async {
  final harness = SalaHarness()
    ..playback.length = _aPart
    ..playback.measured = _aPart
    ..playback.walkWhilePlaying();
  final home = Directory.systemTemp.createTempSync('sala-circulo');
  addTearDown(() => home.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File('${home.path}/p1.m4a')..writeAsBytesSync([1])).path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  harness.room.retroSoFar = BackTranslationProgress(
    segments: [
      SegmentView(
        segmentId: 'trecho-1',
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: toldUpTo,
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  final notifier = container.read(salaSessionProvider.notifier);
  await tester.runAsync(() async {
    await notifier.abrirEscolha();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  await tester.pump(const Duration(milliseconds: 100));
  expect(container.read(salaSessionProvider).stage, SalaStage.retro);
  return (harness, container);
}

void main() {
  group(
    'a resumed Back-translation\'s circle that invites recording opens the Capture on its first tap',
    () {
      for (final (landing, toldUpTo) in [
        ('with ground still to tell', 12000),
        ('told up to the end of its last part', 30000),
      ]) {
        testWidgets(landing, (tester) async {
          final (harness, container) = await _reopenedInto(
            tester,
            toldUpTo: toldUpTo,
          );
          final record = byLabel(retroLabelFor('record', testLanguage));
          final invites = record.evaluate().isNotEmpty;
          if (toldUpTo < _aPart.inMilliseconds) {
            expect(
              invites,
              isTrue,
              reason: 'o círculo convida a gravar onde há chão por contar',
            );
          } else if (!invites) {
            final listen = byLabel(retroLabelFor('listenFirst', testLanguage));
            expect(
              listen,
              findsOneWidget,
              reason: 'nada resta por contar: o círculo não convida a gravar',
            );
            final captures = harness.recorder.captures;
            await tester.tap(listen);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(harness.recorder.captures, captures);
          }

          if (invites) {
            final captures = harness.recorder.captures;
            await tester.tap(record);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await tester.pump(const Duration(milliseconds: 100));

            final state = container.read(salaSessionProvider);
            expect(state.btPhase, BtPhase.capturing);
            expect(state.channel, isA<Microphone>());
            expect(harness.recorder.captures, captures + 1);
            expect(
              byLabel(retroLabelFor('recording', testLanguage)),
              findsOneWidget,
            );
          }
          closeTheRoom(container);
        });
      }
    },
  );
}
