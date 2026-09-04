import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

/// A team standing at the recorded take, with the play/redo/keep row on screen.
Future<ProviderContainer> pumpAoGravado(SalaHarness harness) async {
  final container = await inConversa(harness);
  final notifier = container.read(salaSessionProvider.notifier);

  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();

  return container;
}

void main() {
  group('o play do take', () {
    test('tocar e tocar de novo pausa em vez de recomeçar', () async {
      final harness = SalaHarness();
      final container = await pumpAoGravado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.takePlay();
      await waitFor(
        'o take estar tocando',
        () => container.read(salaSessionProvider).playPing,
      );

      notifier.takePlay();
      await settle();

      expect(
        harness.playback.paused,
        isTrue,
        reason: 'o dublê recebeu pause, não um segundo play',
      );
      expect(
        harness.playback.played.length,
        1,
        reason: 'nenhum novo play — o take não recomeçou',
      );

      final state = container.read(salaSessionProvider);
      expect(state.playPing, isFalse);
      expect(state.takePaused, isTrue);
    });

    test('tocar uma terceira vez retoma de onde parou', () async {
      final harness = SalaHarness();
      final container = await pumpAoGravado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.takePlay();
      await waitFor(
        'o take estar tocando',
        () => container.read(salaSessionProvider).playPing,
      );
      notifier.takePlay();
      await settle();
      notifier.takePlay();
      await settle();

      expect(harness.playback.paused, isFalse, reason: 'o dublê recebeu resume');
      expect(
        harness.playback.played.length,
        1,
        reason: 'sem um novo play — retomou, não recomeçou',
      );

      final state = container.read(salaSessionProvider);
      expect(state.playPing, isTrue);
      expect(state.takePaused, isFalse);
    });

    test('terminar sozinho volta ao começo na próxima vez', () async {
      final harness = SalaHarness();
      final container = await pumpAoGravado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.takePlay();
      await waitFor(
        'o take estar tocando',
        () => container.read(salaSessionProvider).playPing,
      );
      harness.playback.finishPlayback();
      await waitFor(
        'o take parar de tocar sozinho',
        () => !container.read(salaSessionProvider).playPing,
      );

      notifier.takePlay();
      await settle();

      expect(
        harness.playback.played.length,
        2,
        reason: 'um take que terminou sozinho recomeça do zero na próxima vez',
      );
      expect(container.read(salaSessionProvider).playPing, isTrue);
    });

    test('refazer e guardar continuam disponíveis durante e depois de uma pausa',
        () async {
      final harness = SalaHarness();
      final container = await pumpAoGravado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.takePlay();
      await waitFor(
        'o take estar tocando',
        () => container.read(salaSessionProvider).playPing,
      );
      notifier.takePlay();
      await settle();

      expect(container.read(salaSessionProvider).takePaused, isTrue);
      expect(
        container.read(salaSessionProvider).ensaio,
        EnsaioStatus.recorded,
        reason: 'pausado, o take continua oferecendo refazer e guardar',
      );

      notifier.takeKeep();
      await settle();

      expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle);
      expect(container.read(salaSessionProvider).takes, 1);
    });
  });

  group('o ícone segue o estado', () {
    testWidgets('tocando mostra pausa, pausado e parado mostram tocar',
        (tester) async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await tester.pump(const Duration(milliseconds: 100));

      IconData playIcon() => tester
          .widget<Icon>(find.descendant(
            of: byLabel('Ouvir a gravação'),
            matching: find.byType(Icon),
          ))
          .icon!;

      expect(playIcon(), LucideIcons.play, reason: 'take parado mostra tocar');

      await tester.tap(byLabel('Ouvir a gravação'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(playIcon(), LucideIcons.pause, reason: 'tocando mostra pausar');

      await tester.tap(byLabel('Ouvir a gravação'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(playIcon(), LucideIcons.play, reason: 'pausado mostra tocar de novo');
    });
  });
}
