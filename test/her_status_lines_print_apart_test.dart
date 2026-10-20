import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        conferir,
        confirmar,
        contarAteOFimDaParte,
        entrarNaTraducao,
        parte,
        tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show depois, pausarAos, s, traduzirEConfirmar;

const _recomecar = 'recomeçar a tradução';
const _armado = 'toque de novo para apagar as 1 frases traduzidas';
const _recomecada = 'tradução recomeçada — o ensaio da passagem ficou';
const _semFrase = 'ainda não tem frase traduzida';
const _passaDoFim = 'a pausa nova passa do fim da gravação — um pouco antes';
const _barraDaFrase2 = 'Ouvir esta frase de novo e traduzir de novo — 2';

final _duasLacunas = aSpokenWav(gaps: [(s(3.0), s(3.4)), (s(6.0), s(6.4))]);

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _recomecadaComUmaFrase(
  WidgetTester tester,
  SalaHarness harness,
) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  harness.recorder.rehearsalSpeaks = _duasLacunas;
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  await pausarAos(tester, harness, s(4.2));
  await traduzirEConfirmar(tester);
  await waitFor(
    'a primeira frase chegar',
    () => container.read(salaSessionProvider).btTrechos.length == 1,
    step: () => _passo(tester),
  );
  await _passo(tester);
  await tocar(tester, _recomecar);
  await tester.pump(const Duration(milliseconds: 700));
  await tocar(tester, _armado);
  await waitFor(
    'a tradução recomeçar',
    () => container.read(salaSessionProvider).btTrechos.isEmpty,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<void> _duasFrasesComUmAchado(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  for (final (n, toque) in [(1, s(4.2)), (2, s(7.0))]) {
    await pausarAos(tester, harness, toque);
    await traduzirEConfirmar(tester);
    await waitFor(
      'a frase $n chegar à sala',
      () => container.read(salaSessionProvider).btTrechos.length == n,
      step: () => _passo(tester),
    );
  }
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await _passo(tester);
  harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingSegmentId = 'trecho-1';
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

void main() {
  testWidgets(
    'a refused move right after a restart shows her line and the restarted note, each its own line',
    (tester) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        restartLapse: const Duration(minutes: 1),
      );
      final container = await _recomecadaComUmaFrase(tester, harness);
      await _duasFrasesComUmAchado(tester, harness, container);
      harness.room.failReplaceWith = const Refused('PAUSE_PAST_THE_END');
      await tocar(tester, _barraDaFrase2);
      await tocar(tester, depois);
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await tocar(tester, confirmar);
      await waitFor(
        'a recusa chegar',
        () => container.read(salaSessionProvider).btAviso != null,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(find.text(_passaDoFim), findsOneWidget);
      expect(
        find.text(_recomecada),
        findsOneWidget,
        reason: 'a recusa tomava o lugar da nota de recomeço, e só uma ficava',
      );
      expect(
        tester.getTopLeft(find.text(_recomecada)).dy,
        greaterThan(tester.getBottomLeft(find.text(_passaDoFim)).dy),
        reason: 'a nota vem embaixo da linha dela, não em cima',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a «terminei» the check turns back right after a restart shows her line and the restarted note',
    (tester) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        restartLapse: const Duration(minutes: 1),
      );
      final container = await _recomecadaComUmaFrase(tester, harness);
      await pausarAos(tester, harness, s(4.2));
      await traduzirEConfirmar(tester);
      await waitFor(
        'a frase nova chegar',
        () => container.read(salaSessionProvider).btTrechos.length == 1,
        step: () => _passo(tester),
      );
      await contarAteOFimDaParte(tester, harness);
      await waitFor(
        'o terminei acender',
        () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
        step: () => _passo(tester),
      );
      harness.room.verdictRefusal = CheckRefusal.nothingTranslated;
      await tocar(tester, conferir);
      await waitFor(
        'a recusa voltar',
        () => container.read(salaSessionProvider).btRecusa != null,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(find.text(_semFrase), findsOneWidget);
      expect(
        find.text(_recomecada),
        findsOneWidget,
        reason: 'o toque no terminei apagava a nota de recomeço',
      );
      expect(
        tester.getTopLeft(find.text(_recomecada)).dy,
        greaterThan(tester.getBottomLeft(find.text(_semFrase)).dy),
      );
      closeTheRoom(container);
    },
  );
}
