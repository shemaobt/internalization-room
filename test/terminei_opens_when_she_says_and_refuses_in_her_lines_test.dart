import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        confirmar,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tesoura,
        tocar;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _duasFrasesNoTerminei(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocar(tester, tesoura);
  await gravarATraducao(tester);
  await tocar(tester, confirmar);
  await contarAteOFimDaParte(tester, harness);
  await waitFor(
    'o terminei acender',
    () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
    step: () => _passo(tester),
  );
  return container;
}

Future<void> _recusado(WidgetTester tester, ProviderContainer container) async {
  await tocar(tester, conferir);
  await waitFor('a recusa voltar', () {
    final estado = container.read(salaSessionProvider);
    return !estado.btConferindo && estado.btPhase == BtPhase.playing;
  }, step: () => _passo(tester));
  await _passo(tester);
}

void main() {
  test('every refusal the check answers is read by its name, and one this '
      'build does not handle reads as none', () {
    CheckRefusal? lida(Object? code) => BackTranslationVerdict.fromJson({
      'session_id': 'sessao-1',
      'checked': false,
      'refusal': code,
    }).refusal;

    expect(
      [
        lida('FRASE_AWAITING'),
        lida('PART_UNHEARD'),
        lida('NOTHING_TRANSLATED'),
        lida('CHECK_UNAVAILABLE'),
      ],
      [
        CheckRefusal.fraseAwaiting,
        CheckRefusal.partUnheard,
        CheckRefusal.nothingTranslated,
        CheckRefusal.checkUnavailable,
      ],
      reason: 'o app não lia o campo refusal, e toda recusa virava silêncio',
    );
    expect(lida('STRETCH_UNTRANSLATED'), isNull);
    expect(lida(null), isNull);
  });

  testWidgets('a part the player cannot measure, heard to its end with no '
      'frase told, never opens «terminei»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(
      tester,
      harness,
      partes: 1,
      medida: null,
    );

    harness.playback.at = Duration.zero;
    harness.playback.finishPlayback();
    await waitFor(
      'a parte acabar',
      () => container.read(salaSessionProvider).btClipEnded,
      step: () => _passo(tester),
    );

    expect(
      aceso(tester, conferir),
      isFalse,
      reason:
          'uma parte sem medida abria o terminei sem nenhuma frase traduzida',
    );
    await tester.tap(byLabel(conferir));
    await _passo(tester);
    expect(
      harness.room.playedByTakeSent,
      isEmpty,
      reason: 'o toque pedia a conferência de uma tradução que não existe',
    );
    closeTheRoom(container);
  });

  testWidgets('a check refused with nothing translated says so in her words, '
      'voices nothing, and leaves «terminei» to press again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _duasFrasesNoTerminei(tester, harness);
    harness.room.verdictRefusal = CheckRefusal.nothingTranslated;
    harness.voice.refuses.add('');
    final falas = [...harness.voice.played];

    await _recusado(tester, container);

    expect(
      find.text('ainda não tem frase traduzida'),
      findsOneWidget,
      reason: 'a recusa sem frase traduzida não dizia nada na tela',
    );
    expect(
      harness.voice.played,
      falas,
      reason: 'a sala tentava tocar um endereço vazio onde ela não diz nada',
    );
    expect(aceso(tester, conferir), isTrue);
    closeTheRoom(container);
  });
}
