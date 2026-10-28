import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/checagem_externa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaConferida;
import 'fakes.dart' show SalaHarness, closeTheRoom;
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart' show entrarNaTraducao;

void _numa(WidgetTester tester, Size tela) {
  tester.view
    ..physicalSize = tela
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _naRetro(WidgetTester tester, Size tela) async {
  _numa(tester, tela);
  return entrarNaTraducao(tester, SalaHarness(filaEmMemoria: true));
}

Future<ProviderContainer> _noEnsaio(WidgetTester tester, Size tela) async {
  _numa(tester, tela);
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-1843-ensaio').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  final harness = SalaHarness(filaEmMemoria: true, lingua: 'pt');
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = container.read(salaSessionProvider.notifier);
  await tester.runAsync(notifier.abrirEscolha);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(
    () => notifier.goConversa(book: 'Ruth', pericope: 'P01'),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
  return container;
}

Future<ProviderContainer> _naChecagem(WidgetTester tester, Size tela) async {
  final container = await aprovadaNaConferida(
    tester,
    SalaHarness(filaEmMemoria: true),
  );
  _numa(tester, tela);
  for (final botao in ['Checagem externa', 'Novo ouvinte']) {
    await tester.ensureVisible(byLabel(botao).first);
    await tester.tap(byLabel(botao).first, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  expect(container.read(salaSessionProvider).stage, SalaStage.checagem);
  return container;
}

void main() {
  for (final (screen, enter, onAnSE, onAnIPad, hers) in [
    (RetroView, _naRetro, 142.5, 150.0, 'min(38vw,150px), globals.css:429'),
    (
      ChecagemExternaView,
      _naChecagem,
      142.5,
      150.0,
      'min(38vw,150px), globals.css:508',
    ),
    (EnsaioView, _noEnsaio, 172.5, 180.0, 'min(46vw,180px), globals.css:603'),
  ]) {
    for (final (width, height, side) in [
      (375.0, 667.0, onAnSE),
      (768.0, 1024.0, onAnIPad),
    ]) {
      testWidgets('the $screen circle on a ${width.toInt()} wide screen is '
          '${side}pt across, her check circle, not the 160 of every station', (
        tester,
      ) async {
        final container = await enter(tester, Size(width, height));

        expect(
          tester.getSize(
            find.descendant(
              of: find.byType(screen),
              matching: find.byType(FacilitatorCircle),
            ),
          ),
          Size(side, side),
          reason: 'o círculo tinha 160 em toda estação; o dela é $hers',
        );
        closeTheRoom(container);
      });
    }
  }
}
