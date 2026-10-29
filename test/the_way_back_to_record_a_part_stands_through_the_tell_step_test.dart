import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart' show SalaHarness, closeTheRoom, waitFor;
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show contarAteOFimDaParte, entrarNaTraducao;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;
import 'um_ensaio_de_tres_partes.dart';

const _voltar = 'voltar e regravar uma parte';

Finder _naTraducao(String label) =>
    find.descendant(of: find.byType(RetroView), matching: byLabel(label));

bool _aceso(WidgetTester tester) =>
    tester.widget<Semantics>(_naTraducao(_voltar)).properties.enabled == true;

Future<ProviderContainer> _contadaEConferida(
  WidgetTester tester,
  SalaHarness harness,
  BtPhase chega,
) async {
  final container = await entrarNaTraducao(tester, harness);
  await contarAteOFimDaParte(tester, harness);
  await contarAteOFimDaParte(tester, harness);
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == chega,
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  testWidgets(
    'before any verdict «voltar e regravar uma parte» stands under terminei, '
    'live',
    (tester) async {
      final container = await entrarNaTraducao(
        tester,
        SalaHarness(filaEmMemoria: true),
      );

      expect(
        _naTraducao(_voltar),
        findsOneWidget,
        reason:
            'o botão só nascia depois de um veredito, e antes dele a '
            'tradução não tinha caminho de volta para a casa',
      );
      expect(_aceso(tester), isTrue);
      expect(
        tester.getTopLeft(_naTraducao(_voltar)).dy,
        greaterThan(tester.getTopLeft(_naTraducao('terminei')).dy),
        reason: 'o dela fica debaixo do terminei',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'after a clean verdict «voltar e regravar uma parte» still stands, live',
    (tester) async {
      final container = await _contadaEConferida(
        tester,
        SalaHarness(filaEmMemoria: true),
        BtPhase.conferida,
      );

      expect(_naTraducao(_voltar), findsOneWidget);
      expect(
        _aceso(tester),
        isTrue,
        reason:
            'a conferida escondia o caminho de volta, e o dela segue no '
            'passo de contar depois de qualquer veredito',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('«voltar e regravar uma parte» rests while the verdict sounds '
      'again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _contadaEConferida(
      tester,
      harness,
      BtPhase.conferida,
    );

    harness.voice.holdNextLine();
    await tester.tap(_naTraducao('ouvir a resposta de novo'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      _aceso(tester),
      isFalse,
      reason:
          'o botão aceitava um toque com a resposta soando, e o dela '
          'descansa enquanto a resposta fala',
    );

    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_aceso(tester), isTrue);
    closeTheRoom(container);
  });

  test('a fixed line of the room leaves «voltar e regravar uma parte» live, '
      'as hers', () {
    const falando = SalaSessionState(
      machine: Machine(
        station: Retro(),
        channel: GuideSpeaking(
          Line(LineKind.guide, 1, fixedLine: (name: tellLine, language: 'pt')),
        ),
      ),
    );

    expect(falando.btPhase, BtPhase.playing);
    expect(
      falando.canGoBackToRecordAPart,
      isTrue,
      reason:
          'o dela só descansa com a resposta da sala; uma fala fixa '
          'deixa a volta acesa',
    );
  });

  testWidgets('«voltar e regravar uma parte» rests while the room checks the '
      'telling', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    await contarAteOFimDaParte(tester, harness);
    await contarAteOFimDaParte(tester, harness);

    harness.room.holdNextVerdict();
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'a conferência sair para a sala',
      () => container.read(salaSessionProvider).btConferindo,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      _aceso(tester),
      isFalse,
      reason:
          'a volta aceitava um toque com a conferência no ar, e o dela '
          'descansa enquanto a sala confere',
    );

    harness.room.finishHeldVerdict();
    await waitFor(
      'o veredito chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_aceso(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('«voltar e regravar uma parte» rests while a sentence is '
      'recorded again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const []
      ..verdictNamedNuance = const BtFinding(
        kind: BtFindingKind.nuance,
        frase: 4,
        segmentId: 'trecho-4',
      );
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'o veredito chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_aceso(tester), isTrue);

    await tester.ensureVisible(find.text('regravar a frase 4'));
    await tester.tap(find.text('regravar a frase 4'));
    await tester.pump(const Duration(milliseconds: 100));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(salaSessionProvider).btRegravacao, isNotNull);
    expect(
      _aceso(tester),
      isFalse,
      reason:
          'com «regravar a frase 4» aberto a volta seguia acesa, e a dela '
          'espera a frase terminar',
    );
    closeTheRoom(container);
  });

  test(
    '«voltar e regravar uma parte» rests while an approval is in the air',
    () {
      const aprovando = SalaSessionState(
        machine: Machine(station: Retro(), generation: 3),
        btPhase: BtPhase.conferida,
        btAprovando: 3,
      );

      expect(
        aprovando.canGoBackToRecordAPart,
        isFalse,
        reason:
            'a volta saía com a aprovação no ar, e o dela descansa enquanto '
            'a aprovação confere',
      );
    },
  );

  testWidgets('a tap on «voltar e regravar uma parte» stops every sound and '
      'says nothing on the home', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final desde = harness.sounds.length;

    await tester.ensureVisible(_naTraducao(_voltar));
    await tester.tap(_naTraducao(_voltar));
    await tester.pump(const Duration(milliseconds: 400));
    final depois = harness.sounds.sublist(desde);

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(
      depois,
      containsAll(['playback:stop', 'voice:stop']),
      reason: 'a gravação seguia tocando por baixo da casa',
    );
    expect(
      depois.where(
        (som) => const [
          'voice:line',
          'voice:fixed',
          'voice:asset',
          'playback:play',
        ].contains(som),
      ),
      isEmpty,
      reason: 'o dela volta à casa sem dizer nada',
    );
    closeTheRoom(container);
  });

  test('the way back to the home lets go of a frase chosen to be told '
      'again', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    it.sala.traduzirAFraseDeNovo(0);
    await waitFor(
      'a frase ficar escolhida para traduzir de novo',
      () => it.estado.btTrechoTraduzidoDeNovo != null,
    );
    expect(it.estado.btTraducaoPendente, isNotNull);

    it.sala.leaveTheBackTranslation();
    await waitFor('a casa abrir', () => it.estado.stage == SalaStage.ensaio);

    expect(it.estado.btTrechoTraduzidoDeNovo, isNull);
    expect(
      it.estado.btTraducaoPendente,
      isNull,
      reason:
          'a tradução escolhida para refazer ficava pendurada na casa, e o '
          'dela larga a frase aberta ao sair',
    );
  });

  testWidgets('«voltar e regravar uma parte» stays live while the room says '
      'how to tell, after the telling starts over', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    await contarAteOFimDaParte(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 700));
    harness.voice.holdNextLine();
    notifier.recomecarATraducao();
    await waitFor(
      'a sala falar como contar',
      () => container.read(salaSessionProvider).channel is GuideSpeaking,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.room.restartsAsked, isNotEmpty);
    expect(
      _aceso(tester),
      isTrue,
      reason:
          'a fala fixa depois do recomeço apagava a volta, e no dela toda '
          'fala fixa deixa a volta acesa',
    );

    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 100));
    closeTheRoom(container);
  });
}
