import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/status_lines.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show conferir, contarAteOFimDaParte, entrarNaTraducao, parte, tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show depois, pausarAos, s, traduzirEConfirmar;

const _recomecar = 'recomeçar a tradução';
const _armado = 'toque de novo para apagar as 1 frases traduzidas';
const _recomecada = 'tradução recomeçada — o ensaio da passagem ficou';
const _semFrase = 'ainda não tem frase traduzida';
const _passaDoFim = 'a pausa nova passa do fim da gravação — um pouco antes';
Color? _tinta(WidgetTester tester, String texto) =>
    tester.widget<Text>(find.text(texto)).style?.color;

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
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.playing &&
        container.read(salaSessionProvider).btVeredito,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

Future<ProviderContainer> _movidaRecusadaDepoisDeRecomecar(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _recomecadaComUmaFrase(tester, harness);
  await _duasFrasesComUmAchado(tester, harness, container);
  harness.room.failReplaceWith = const Refused('PAUSE_PAST_THE_END');
  await tocar(tester, _barraDaFrase2);
  await tocar(tester, depois);
  await tocar(tester, 'Tocar para gravar a tradução de novo');
  await tocar(tester, 'Tocar ao terminar');
  await waitFor(
    'a recusa chegar',
    () => container.read(salaSessionProvider).btAviso != null,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

void main() {
  testWidgets(
    'a refused move right after a restart shows her line and the restarted note, each its own line',
    (tester) async {
      final container = await _movidaRecusadaDepoisDeRecomecar(
        tester,
        SalaHarness(
          filaEmMemoria: true,
          restartLapse: const Duration(minutes: 1),
        ),
      );

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
      expect(
        _tinta(tester, _passaDoFim),
        const Color(0xFF3F3E20),
        reason: 'a linha dela saía no terracota da tela, não no verde dela',
      );
      expect(
        _tinta(tester, _recomecada),
        const Color(0xFF6D6C56),
        reason: 'a nota saía no terracota da tela, não no verde claro dela',
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
      expect(
        _tinta(tester, _semFrase),
        const Color(0xFF3F3E20),
        reason: 'a recusa do terminei saía no terracota, não no verde dela',
      );
      closeTheRoom(container);
    },
  );

  for (final (tema, status, nota) in [
    (AppTheme.light, const Color(0xFF3F3E20), const Color(0xFF6D6C56)),
    (AppTheme.dark, const Color(0xFFECEADC), const Color(0xFFA79E8C)),
  ]) {
    testWidgets(
      'the status line reads in her verde and the note beneath it in her verde claro, in ${tema.brightness.name}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: tema,
            home: const StatusLines(line: 'a linha', note: 'a nota'),
          ),
        );

        expect(
          _tinta(tester, 'a linha'),
          status,
          reason: 'a linha de estado não lia no verde dela',
        );
        expect(
          _tinta(tester, 'a nota'),
          nota,
          reason: 'a nota de recomeço não lia no verde claro dela',
        );
      },
    );
  }

  testWidgets(
    'a frase bar tapped after a restart writes the retelling line and keeps the restarted note',
    (tester) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        restartLapse: const Duration(seconds: 20),
      );
      final container = await _recomecadaComUmaFrase(tester, harness);
      await _duasFrasesComUmAchado(tester, harness, container);
      expect(find.text(_recomecada), findsOneWidget);

      await tocar(tester, _barraDaFrase2);

      expect(find.text(_recomecada), findsOneWidget);
      expect(find.textContaining('traduzindo de novo a frase'), findsOneWidget);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a refusal that lands inside the six seconds of the restarted note stays when the note goes',
    (tester) async {
      final container = await _movidaRecusadaDepoisDeRecomecar(
        tester,
        SalaHarness(
          filaEmMemoria: true,
          restartLapse: const Duration(seconds: 20),
        ),
      );
      expect(find.text(_recomecada), findsOneWidget);

      await tester.pump(const Duration(seconds: 20));

      expect(find.text(_recomecada), findsNothing);
      expect(
        find.text(_passaDoFim),
        findsOneWidget,
        reason: 'o relógio da nota levava a recusa dela junto',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'on a phone as narrow as the iPhone SE a refusal keeps the margin the frase rows keep, not the screen edge',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      tester.view
        ..physicalSize = const Size(375, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      harness.recorder.rehearsalSpeaks = _duasLacunas;
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      await pausarAos(tester, harness, s(4.2));
      await traduzirEConfirmar(tester);
      await waitFor(
        'a frase chegar',
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

      final linha = tester.getRect(find.text(_semFrase));
      expect(
        linha.left,
        16,
        reason: 'a recusa encostava na borda esquerda do iPhone SE',
      );
      expect(
        linha.right,
        375 - 16,
        reason: 'a recusa encostava na borda direita do iPhone SE',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a single refusal sits twelve points under the circle\'s ring, not on it',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      tester.view
        ..physicalSize = const Size(820, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      harness.recorder.rehearsalSpeaks = _duasLacunas;
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      await pausarAos(tester, harness, s(4.2));
      await traduzirEConfirmar(tester);
      await waitFor(
        'a frase chegar',
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

      expect(
        tester.getTopLeft(find.text(_semFrase)).dy -
            tester.getBottomLeft(find.byType(FacilitatorCircle)).dy,
        46.5,
        reason: 'a linha de estado ficava dentro do anel do círculo',
      );
      closeTheRoom(container);
    },
  );
}
