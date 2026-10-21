import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, confirmar, entrarNaTraducao, ouvir, parte, passaDoCursor, tocar;

const tesoura = 'Pausar onde a frase acaba';
const antes = 'um pouco antes';
const ouvirAPausa = 'ouvir a pausa';
const depois = 'um pouco depois';
const dica =
    'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo '
    'para traduzir';
const dicaNoToque = 'a pausa ficou no toque — toquem no círculo para traduzir';

const scissors = 'Pause where the sentence ends';
const earlier = 'a little earlier';
const hearThePause = 'hear the pause';
const later = 'a little later';
const hint =
    'the pause is here — listen, move it if you need to, then tap the circle '
    'to translate';
const hintAtTheTap = 'the pause is at your tap — tap the circle to translate';

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

final umaLacunaAos3 = aSpokenWav(gaps: [(s(3.0), s(3.4))]);

Future<ProviderContainer> entrarComAFala(
  WidgetTester tester,
  SalaHarness harness,
  Uint8List? fala,
) {
  harness.recorder.rehearsalSpeaks = fala;
  return entrarNaTraducao(tester, harness, partes: 1);
}

Future<void> pausarAos(
  WidgetTester tester,
  SalaHarness harness,
  Duration toque, {
  String rotulo = tesoura,
}) async {
  harness.playback.at = toque;
  await tester.pump(passaDoCursor);
  await tocar(tester, rotulo);
}

Finder circulo() => find.descendant(
  of: find.byType(RetroView),
  matching: find.byType(FacilitatorCircle),
);

Future<void> tocarOCirculo(WidgetTester tester) async {
  await tester.tap(circulo());
  await tester.pump(const Duration(milliseconds: 300));
}

String rotuloDoCirculo(WidgetTester tester) =>
    tester.widget<FacilitatorCircle>(circulo()).semanticLabel;

Future<void> traduzirEConfirmar(WidgetTester tester) async {
  await tocarOCirculo(tester);
  await tocarOCirculo(tester);
  await tocar(tester, confirmar);
}

Duration pausa(ProviderContainer container) =>
    container.read(salaSessionProvider).btCorte;

Future<void> aDicaEOsTresControles(
  WidgetTester tester, {
  required String language,
  required String aDica,
  required List<String> controles,
  required String aTesoura,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, lingua: language);
  final container = await entrarComAFala(tester, harness, umaLacunaAos3);
  await pausarAos(tester, harness, s(4.2), rotulo: aTesoura);
  final semantics = tester.ensureSemantics();

  expect(rotuloDoCirculo(tester), aDica);
  for (final controle in controles) {
    expect(aceso(tester, controle), isTrue, reason: controle);
  }
  final ondeEstao = [
    for (final controle in controles) tester.getCenter(byLabel(controle)).dx,
  ];
  expect(ondeEstao, [...ondeEstao]..sort(), reason: 'na ordem dela');
  expect(
    find.bySemanticsLabel(RegExp('cort|Cut', caseSensitive: false)),
    findsNothing,
  );
  semantics.dispose();
  closeTheRoom(container);
}

void main() {
  testWidgets('a pause tapped 0.8 s after a clear gap lands in the middle of '
      'that gap', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);

    await pausarAos(tester, harness, s(4.2));

    expect(pausa(container), s(3.2));
    closeTheRoom(container);
  });

  testWidgets('a pause with silence only 2 s earlier stays at the tap', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(
      tester,
      harness,
      aSpokenWav(gaps: [(s(1.9), s(2.2))]),
    );

    await pausarAos(tester, harness, s(4.2));

    expect(pausa(container), s(4.2));
    closeTheRoom(container);
  });

  testWidgets('«um pouco antes» moves the pausa earlier and «ouvir a pausa» '
      'plays the moment before it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    await tocar(tester, antes);

    expect(
      pausa(container),
      s(2.8),
      reason: 'nenhum silêncio antes em 1,5 s: 0,4 s mais cedo',
    );

    await tocar(tester, ouvirAPausa);

    expect(harness.playback.ranges.last, '1300-2800');
    closeTheRoom(container);
  });

  testWidgets('after a pause the screen offers her hint and her three controls '
      'and no «Cortar aqui»', (tester) async {
    await aDicaEOsTresControles(
      tester,
      language: 'pt',
      aDica: dica,
      controles: [antes, ouvirAPausa, depois],
      aTesoura: tesoura,
    );
  });

  testWidgets('after a pause the english screen offers her hint and her three '
      'controls and no "Cut here"', (tester) async {
    await aDicaEOsTresControles(
      tester,
      language: 'en',
      aDica: hint,
      controles: [earlier, hearThePause, later],
      aTesoura: scissors,
    );
  });

  testWidgets('the scissors pressed while «ouvir a pausa» plays place the '
      'pausa where the team hears it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(
      tester,
      harness,
      aSpokenWav(gaps: [(s(3.0), s(3.4)), (s(5.0), s(5.4))]),
    );
    await pausarAos(tester, harness, s(6.2));
    expect(pausa(container), s(5.2));
    await tocar(tester, ouvirAPausa);
    expect(harness.playback.ranges.last, '3700-5200');

    harness.playback.at = s(0.8);
    await tocar(tester, tesoura);

    expect(
      pausa(container),
      s(3.2),
      reason: 'ouvido aos 4,5 s da parte, o silêncio mais perto é o dos 3 s',
    );
    closeTheRoom(container);
  });

  testWidgets('the scissors tapped twice while «ouvir a pausa» plays read '
      'the head in the part both times', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(
      tester,
      harness,
      aSpokenWav(gaps: [(s(3.1), s(3.3)), (s(4.0), s(4.4))]),
    );
    await pausarAos(tester, harness, s(3.0));
    await tocar(tester, depois);
    expect(pausa(container), s(4.2));
    await tocar(tester, ouvirAPausa);
    expect(harness.playback.ranges.last, '2700-4200');
    harness.playback.at = s(1.0);
    await tocar(tester, tesoura);
    expect(pausa(container), s(3.2));
    harness.playback.at = s(1.0);

    await tocar(tester, tesoura);

    expect(pausa(container), s(3.2));
    closeTheRoom(container);
  });

  testWidgets('the scissors after «ouvir a pausa» read the head in the part, '
      'not in the clip just heard', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(
      tester,
      harness,
      aSpokenWav(gaps: [(s(3.1), s(3.3))]),
    );
    await pausarAos(tester, harness, s(3.0));
    expect(pausa(container), s(3.2));
    await tocar(tester, ouvirAPausa);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = s(1.5);

    await tocar(tester, tesoura);

    expect(pausa(container), s(3.2));
    closeTheRoom(container);
  });

  testWidgets('after a nudge nothing the team plays ends at the old pausa', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));
    await tocar(tester, ouvirAPausa);
    expect(harness.playback.ranges.last, '1700-3200');

    await tocar(tester, antes);
    await tocar(tester, ouvir);

    expect(harness.playback.ranges.last, endsWith('-2800'));
    closeTheRoom(container);
  });

  testWidgets('a pausa then translated ends the stretch at the snapped pausa', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    await traduzirEConfirmar(tester);

    expect(harness.room.chunkSpans.last, '0-3200');
    expect(container.read(salaSessionProvider).btTrechos.last.to, s(3.2));
    expect(
      harness.playback.playedFrom.last,
      s(3.2),
      reason: 'a parte segue da pausa, não do toque',
    );
    closeTheRoom(container);
  });

  testWidgets('a part with no envelope keeps the pausa at the tap', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);

    await pausarAos(tester, harness, s(4));

    expect(pausa(container), s(4));
    expect(rotuloDoCirculo(tester), dicaNoToque);
    for (final controle in [antes, ouvirAPausa, depois]) {
      expect(aceso(tester, controle), isFalse, reason: controle);
    }
    closeTheRoom(container);
  });

  testWidgets('a part with no envelope keeps the pausa at the tap, said in '
      'english', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarComAFala(tester, harness, null);

    await pausarAos(tester, harness, s(4), rotulo: scissors);

    expect(pausa(container), s(4));
    expect(rotuloDoCirculo(tester), hintAtTheTap);
    for (final controle in [earlier, hearThePause, later]) {
      expect(aceso(tester, controle), isFalse, reason: controle);
    }
    closeTheRoom(container);
  });

  testWidgets('the pausa never comes closer to the cursor than a shortest '
      'stretch', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));
    await traduzirEConfirmar(tester);
    expect(container.read(salaSessionProvider).btCursor, s(3.2));

    await pausarAos(tester, harness, s(3.6));

    expect(
      pausa(container),
      s(3.4),
      reason: 'o silêncio cruza o cursor: a pausa fica 200 ms depois dele',
    );
    closeTheRoom(container);
  });

  testWidgets('a circle tap 0.1 s after the last pausa tells a frase of 0.2 s, '
      'not a sliver', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    await pausarAos(tester, harness, s(4));
    await traduzirEConfirmar(tester);
    expect(container.read(salaSessionProvider).btCursor, s(4));

    harness.playback.at = s(4.1);
    await tester.pump(passaDoCursor);
    await traduzirEConfirmar(tester);

    expect(
      harness.room.chunkSpans.last,
      '4000-4200',
      reason: 'sem envelope a pausa ficava no toque e a frase tinha 0,1 s',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a tap with less than 0.2 s of the part left after the last pausa '
    'tells nothing, not a sliver',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarComAFala(tester, harness, null);
      await pausarAos(tester, harness, s(9.9));
      await traduzirEConfirmar(tester);
      expect(harness.room.chunkSpans, ['0-9900']);

      harness.playback.at = s(9.95);
      await tester.pump(passaDoCursor);
      await traduzirEConfirmar(tester);

      expect(
        harness.room.chunkSpans,
        ['0-9900'],
        reason:
            'o teto do piso levava a pausa ao fim e mandava uma frase de 0,1 s',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the scissors with less than 0.2 s of the part left place no '
      'pausa either', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    await pausarAos(tester, harness, s(9.9));
    await traduzirEConfirmar(tester);
    expect(harness.room.chunkSpans, ['0-9900']);

    await pausarAos(tester, harness, s(9.95));
    await traduzirEConfirmar(tester);

    expect(
      harness.room.chunkSpans,
      ['0-9900'],
      reason: 'a tesoura punha a pausa no fim e o círculo mandava 0,1 s',
    );
    closeTheRoom(container);
  });

  testWidgets('a tail of 0.3 s left at the end of the part is not offered as a '
      'frase', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(9.7));
    await traduzirEConfirmar(tester);
    expect(harness.room.chunkSpans, ['0-9700']);

    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await traduzirEConfirmar(tester);

    expect(
      harness.room.chunkSpans,
      ['0-9700'],
      reason: 'o círculo abria o microfone e os 0,3 s do fim viravam uma frase',
    );
    closeTheRoom(container);
  });

  testWidgets('the pausa never goes past the part\'s end', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    for (var vez = 0; vez < 20; vez++) {
      await tocar(tester, depois);
    }

    expect(pausa(container), parte - s(0.1));
    closeTheRoom(container);
  });

  testWidgets('the three controls stay in the row, dimmed, while no pausa '
      'stands', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);

    for (final controle in [antes, ouvirAPausa, depois]) {
      expect(aceso(tester, controle), isFalse, reason: 'antes da pausa');
    }

    await tocar(tester, tesoura);
    await tocarOCirculo(tester);
    await tocarOCirculo(tester);

    for (final controle in [antes, ouvirAPausa, depois]) {
      expect(aceso(tester, controle), isFalse, reason: 'a tradução já gravada');
    }
    closeTheRoom(container);
  });

  test('no label the team reads says corte, cortar or cut', () {
    final rotulos = <Map<String, String>>[
      ...circleLabels.values,
      ...retroLabels.values,
      ...rehearsalLabels.values,
      ...findingLabels.values,
      ...escolhaLabels.values,
      ...handLabels.values,
      ...roomLabels.values,
      warningNoticeLabel,
      ...codigoLabels.values,
      recordEntryLabel,
      ...momentLabels.values,
      momentAria,
    ];
    final proibida = RegExp('cort|cut', caseSensitive: false);
    for (final rotulo in rotulos) {
      for (final language in languages) {
        expect(rotulo[language], isNot(matches(proibida)), reason: '$rotulo');
      }
    }
  });

  testWidgets('the circle\'s own capture ends its stretch at a snapped pausa '
      'too', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);

    await traduzirEConfirmar(tester);

    expect(harness.room.chunkSpans.last, '0-3200');
    closeTheRoom(container);
  });

  testWidgets('a part told to its end ends its stretch at the part end, not at '
      'its last silence', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(
      tester,
      harness,
      aSpokenWav(gaps: [(s(3.0), s(3.4)), (s(9.0), s(9.4))]),
    );
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await traduzirEConfirmar(tester);

    expect(harness.room.chunkSpans.last, '0-10000');
    closeTheRoom(container);
  });
}
