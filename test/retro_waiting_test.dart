import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

const cortar = 'Cortar aqui e contar esta parte';
const contar = 'Contar esta parte na língua ponte';

/// A team told the rehearsal and is standing in the telling-back, with the recording in
/// the air — which is how the room hands the phase over.
Future<ProviderContainer> pumpToContarDeVolta(
  WidgetTester tester,
  SalaHarness harness,
) async {
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
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

/// Stop the recording where the team stopped listening.
Future<void> pararAGravacao(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(salaSessionProvider.notifier).ouvirGravacao();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<SalaHarness> pumpToRestartInFlight(WidgetTester tester) async {
  final harness = SalaHarness()
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition;
  final container = await pumpToContarDeVolta(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);

  harness.playback.at = const Duration(seconds: 10);
  notifier.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));

  expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);

  harness.room.holdNextTurn();
  unawaited(notifier.reRecordClip());
  await tester.pump(const Duration(milliseconds: 200));
  return harness;
}

void main() {
  testWidgets('with the recording in the air the button offers to cut',
      (tester) async {
    await pumpToContarDeVolta(tester, SalaHarness());

    expect(byLabel(cortar), findsOneWidget,
        reason: 'com o áudio correndo sob o dedo existe um instante sendo '
            'apontado, e é isso que a equipe está escolhendo ao tocar');
  });

  testWidgets('with the recording stopped the same button offers to tell',
      (tester) async {
    final container = await pumpToContarDeVolta(tester, SalaHarness());
    await pararAGravacao(tester, container);

    expect(byLabel(contar), findsOneWidget,
        reason: 'parado não há instante nenhum sendo apontado, e um botão que '
            'promete cortar aqui não descreve mais nada — o que resta do '
            'gesto é contar');
    expect(byLabel(cortar), findsNothing,
        reason: 'e só uma das duas caras por vez: um botão que oferecesse as '
            'duas ao mesmo tempo não diria nada sobre o que vai acontecer');
  });

  for (final noAr in [true, false]) {
    testWidgets(
        'the tap lands in the same place with the recording '
        '${noAr ? "in the air" : "stopped"}', (tester) async {
      final container = await pumpToContarDeVolta(tester, SalaHarness());
      if (!noAr) await pararAGravacao(tester, container);

      await tester.tap(byLabel(noAr ? cortar : contar));
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
          reason: 'a cara do botão muda, o que ele faz não: nos dois estados o '
              'toque abre o microfone para a equipe contar esta parte, e um '
              'botão que mudasse de destino junto com o rótulo trocaria o '
              'fluxo por baixo de uma mudança de palavra');
    });
  }

  testWidgets('the listening button is left alone', (tester) async {
    final container = await pumpToContarDeVolta(tester, SalaHarness());

    expect(byLabel('Pausar a gravação'), findsOneWidget,
        reason: 'o botão de ouvir tem a sua própria fala e ela já segue o '
            'player; o vizinho mudar de cara não pode arrastá-lo junto');

    await pararAGravacao(tester, container);

    expect(byLabel('Ouvir a gravação'), findsOneWidget,
        reason: 'e parado ele volta a oferecer ouvir, como sempre ofereceu');
  });

  testWidgets('the findings screen offers nothing to tap while the room is '
      'restarting the clip', (tester) async {
    await pumpToRestartInFlight(tester);

    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.byType(RoundActionButton),
      ),
      findsNothing,
      reason: 'a equipe agia dentro da espera e o app ficava segurando trechos '
          'que a sessão já tinha descartado',
    );
  });

  testWidgets('the circle shows the room is busy while it restarts the clip',
      (tester) async {
    await pumpToRestartInFlight(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is FacilitatorCircle && widget.voice == VoiceState.thinking,
      ),
      findsOneWidget,
      reason: 'a tela não tem uma palavra legível: sumir com os botões e deixar '
          'a sala parada faria a equipe tocar de novo sem entender',
    );
  });
}
