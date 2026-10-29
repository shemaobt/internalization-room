import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, entrarNaTraducao, ouvir, parte, passaDoCursor, pausado, tocar;

const antes = 'um pouco antes';
const ouvirAPausa = 'ouvir a pausa';
const depois = 'um pouco depois';
const dica =
    'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo '
    'para traduzir';
const dicaNoToque = 'a pausa ficou no toque — toquem no círculo para traduzir';

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
  Duration toque,
) async {
  harness.playback.at = toque;
  await tester.pump(passaDoCursor);
  await tocarOCirculo(tester);
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
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pausarETraduzir(WidgetTester tester) async {
  await tocarOCirculo(tester);
  await traduzirEConfirmar(tester);
}

Duration pausa(ProviderContainer container) =>
    container.read(salaSessionProvider).btCorte;

Future<void> aDicaEOsTresControles(
  WidgetTester tester, {
  required String language,
  required String aDica,
  required List<String> controles,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, lingua: language);
  final container = await entrarComAFala(tester, harness, umaLacunaAos3);
  await pausarAos(tester, harness, s(4.2));
  final semantics = tester.ensureSemantics();

  expect(rotuloDoCirculo(tester), aDica);
  for (final controle in controles) {
    expect(aceso(tester, controle), isTrue, reason: controle);
    expect(
      find.descendant(of: byLabel(controle), matching: find.text(controle)),
      findsOneWidget,
      reason:
          'o controle era um ícone, e a palavra dela só o leitor de tela dizia',
    );
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
    );
  });

  testWidgets('after a pause the english screen offers her hint and her three '
      'controls and no "Cut here"', (tester) async {
    await aDicaEOsTresControles(
      tester,
      language: 'en',
      aDica: hint,
      controles: [earlier, hearThePause, later],
    );
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

    await pausarAos(tester, harness, s(4));

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
    await pausarETraduzir(tester);

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
      expect(container.read(salaSessionProvider).btClipRodando, isTrue);

      await tocarOCirculo(tester);

      expect(
        container.read(salaSessionProvider).btClipRodando,
        isFalse,
        reason: 'como no dela, o toque pausa a gravação mesmo sem frase',
      );
      expect(harness.playback.sounding, isFalse);
      expect(rotuloDoCirculo(tester), pausado);

      await tocarOCirculo(tester);
      await tocarOCirculo(tester);

      expect(
        harness.room.chunkSpans,
        ['0-9900'],
        reason:
            'o teto do piso levava a pausa ao fim e mandava uma frase de 0,1 s',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('a part the player could not measure keeps the 0.2 s room inside '
      'its own length', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.recorder.rehearsalSpeaks = umaLacunaAos3;
    final container = await entrarNaTraducao(
      tester,
      harness,
      partes: 1,
      medida: null,
    );
    harness.playback.length = parte;
    await pausarAos(tester, harness, s(9.95));
    await traduzirEConfirmar(tester);
    expect(harness.room.chunkSpans, ['0-9900']);

    harness.playback.at = s(9.95);
    await tester.pump(passaDoCursor);
    await pausarETraduzir(tester);

    expect(
      harness.room.chunkSpans,
      ['0-9900'],
      reason: 'sem medida o piso ficava sem teto e a frase passava do fim',
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
    await pausarETraduzir(tester);

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

    await tocarOCirculo(tester);
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
      ...recordingHomeLabels.values,
      ...findingLabels.values,
      ...escolhaLabels.values,
      ...handLabels.values,
      ...roomLabels.values,
      ...codigoLabels.values,
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

    await pausarETraduzir(tester);

    expect(harness.room.chunkSpans.last, '0-3200');
    closeTheRoom(container);
  });

  testWidgets('the check offers no scissors and no green confirm', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);

    expect(
      byLabel('Pausar onde a frase acaba'),
      findsNothing,
      reason: 'a tesoura é a pausa do círculo, e a dela não tem tesoura',
    );
    expect(
      byLabel('Confirmar a tradução e seguir'),
      findsNothing,
      reason: 'o terceiro toque manda a frase; o botão verde era um quarto',
    );
    closeTheRoom(container);
  });

  testWidgets('at the end of the recording the first tap places the pausa at '
      'the end of the take and opens no microphone, the second opens it, the '
      'third sends the frase to the end', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(salaSessionProvider).btClipEnded, isTrue);

    await tocarOCirculo(tester);
    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.playing,
      reason: 'no fim da gravação o primeiro toque já abria o microfone',
    );
    expect(pausa(container), parte);

    await tocarOCirculo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);

    await tocarOCirculo(tester);
    await waitFor(
      'a frase chegar à sala',
      () => harness.room.chunkSpans.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    expect(harness.room.chunkSpans, ['0-10000']);
    closeTheRoom(container);
  });

  testWidgets('the first tap on the circle pauses at the snapped pausa and '
      'opens no microphone', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);

    await tocarOCirculo(tester);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.playing,
      reason:
          'o primeiro toque abria o microfone, e a pausa não tinha como ser '
          'ajustada antes de traduzir',
    );
    expect(harness.playback.sounding, isFalse);
    expect(pausa(container), s(3.2));
    expect(aceso(tester, depois), isTrue);
    closeTheRoom(container);
  });

  testWidgets('three taps on the circle tell one frase ending in the nearest '
      'silence, and the recording goes on from it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);

    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    await tocarOCirculo(tester);
    await waitFor(
      'a frase chegar à sala',
      () => harness.room.chunkSpans.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.room.chunkSpans,
      ['0-3200'],
      reason:
          'o terceiro toque só fechava o microfone; a frase esperava um botão '
          'verde que ela não tem',
    );
    expect(harness.playback.playedFrom.last, s(3.2));
    closeTheRoom(container);
  });

  testWidgets('after the first tap «um pouco depois» moves the pausa later, '
      '«ouvir a pausa» plays up to it, and the frase ends there', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);
    await tocarOCirculo(tester);

    await tocar(tester, depois);
    expect(
      pausa(container),
      s(3.6),
      reason: 'nenhum silêncio depois em 1,5 s: 0,4 s mais tarde',
    );
    await tocar(tester, ouvirAPausa);
    expect(harness.playback.ranges.last, '2100-3600');

    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await waitFor(
      'a frase chegar à sala',
      () => harness.room.chunkSpans.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    expect(
      harness.room.chunkSpans,
      ['0-3600'],
      reason: 'pelo círculo a pausa nunca podia ser ajustada',
    );
    closeTheRoom(container);
  });

  testWidgets('after a frase the room refused, the next tap records it again '
      'and the tap after sends the new recording', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await waitFor(
      'a recusa voltar',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    harness.room.failChunkWith = null;

    await tocarOCirculo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    await tocarOCirculo(tester);
    await waitFor(
      'a frase chegar à sala',
      () => harness.room.chunkSpans.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(
      harness.room.chunkSpans,
      ['0-3200'],
      reason:
          'sem o botão verde, a frase recusada não tinha outro caminho até a '
          'sala',
    );
    closeTheRoom(container);
  });

  testWidgets('a recording that comes back empty sends nothing, not even the '
      'frase refused before it, and the pausa stays', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    harness.playback.at = s(4.2);
    await tester.pump(passaDoCursor);
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await waitFor(
      'a recusa voltar',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    harness.room.failChunkWith = null;
    harness.recorder.returnsEmpty = true;

    await tocarOCirculo(tester);
    await tocarOCirculo(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.chunkSpans,
      isEmpty,
      reason:
          'o toque que fecha uma gravação vazia mandava a tradução recusada '
          'que ainda estava guardada',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(pausa(container), s(3.2));
    harness.recorder.returnsEmpty = false;
    await tocarOCirculo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
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

    await pausarETraduzir(tester);

    expect(harness.room.chunkSpans.last, '0-10000');
    closeTheRoom(container);
  });
}
