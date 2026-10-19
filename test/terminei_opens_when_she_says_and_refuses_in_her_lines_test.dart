import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, conferir, entrarNaTraducao;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

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
}
