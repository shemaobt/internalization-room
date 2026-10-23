import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_resumed_back_translation_circle_opens_the_microphone_test.dart'
    show reopenedInto;
import 'fakes.dart';
import 'o_take_pausa_test.dart' show pumpAoGravado;
import 'scenario_helpers.dart' show byLabel, settle;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        fimDaGravacao,
        ouvindo,
        parte,
        passaDoCursor,
        pausado,
        pausar,
        terminar,
        tocar,
        tocarNoCirculo;
import 'the_pause_snaps_to_silence_test.dart'
    show
        entrarComAFala,
        pausa,
        rotuloDoCirculo,
        s,
        tocarOCirculo,
        traduzirEConfirmar,
        umaLacunaAos3;

void main() {
  test('a take held in the Ensaio is not a clip held on the check', () async {
    final harness = SalaHarness();
    final container = await pumpAoGravado(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.playTheRehearsal();
    await waitFor(
      'o take estar tocando',
      () => container.read(salaSessionProvider).playPing,
    );

    notifier.playTheRehearsal();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.takePaused, isTrue);
    expect(
      state.btClipPausada,
      isFalse,
      reason: 'o take parado no ensaio se dizia um clipe parado da tradução',
    );
  });

  testWidgets('a part running past the cursor reads her «ouvindo a gravação '
      'de vocês…», not the invitation to record', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    expect(container.read(salaSessionProvider).btClipRodando, isTrue);
    expect(
      rotuloDoCirculo(tester),
      'ouvindo a gravação de vocês…',
      reason: 'o círculo convidava a gravar com a gravação tocando',
    );
    closeTheRoom(container);
  });

  testWidgets('a part running before its head passes the cursor reads her '
      '«ouvindo a gravação de vocês…», not listen first', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);

    final state = container.read(salaSessionProvider);
    expect(state.btClipRodando, isTrue);
    expect(state.nothingHeardSinceCursor, isTrue);
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason: 'a parte tocando antes do cursor dizia ouvir primeiro',
    );
    closeTheRoom(container);
  });

  testWidgets('an english room hears its recording played in english, not in '
      'portuguese', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    expect(
      rotuloDoCirculo(tester),
      'listening to your recording…',
      reason: 'o rótulo da gravação tocando ficava em português',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase told again reads her «ouvindo a gravação de vocês…» '
      'while it plays, not the invitation to record', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await umaFraseConferida(tester, harness);

    container.read(salaSessionProvider.notifier).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(salaSessionProvider);
    expect(state.btTrechoTraduzidoDeNovo, isNotNull);
    expect(state.btTrechoTocando, isTrue);
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason: 'a frase traduzida de novo tocava sob o convite a gravar',
    );
    closeTheRoom(container);
  });

  testWidgets('a bead replaying the recording reads her «ouvindo a gravação '
      'de vocês…», not the invitation to record', (tester) async {
    final (harness, container) = await reopenedInto(tester, toldUpTo: 5000);

    container.read(salaSessionProvider.notifier).ouvirAConta(0);
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(salaSessionProvider);
    expect(state.btTrechos.first.retroPath, isNull);
    expect(state.btTrechoTocando, isTrue);
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason: 'a conta tocando a gravação dizia para gravar a tradução',
    );
    harness.playback.stopWalking();
    closeTheRoom(container);
  });

  testWidgets('a bead replaying the recording at its end reads her «ouvindo a '
      'gravação de vocês…», not the end of the recording', (tester) async {
    final (harness, container) = await reopenedInto(tester, toldUpTo: 5000);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(salaSessionProvider).btClipEnded, isTrue);
    expect(rotuloDoCirculo(tester), fimDaGravacao);

    container.read(salaSessionProvider.notifier).ouvirAConta(0);
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue);
    expect(state.btTrechoTocando, isTrue);
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason: 'a conta tocando a gravação no fim dizia fim da gravação',
    );
    harness.playback.stopWalking();
    closeTheRoom(container);
  });

  testWidgets('a loudspeaker playing its translation does not say the '
      'recording is playing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await umaFraseContada(tester, harness);

    container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btRetroTocando, isTrue);
    expect(
      rotuloDoCirculo(tester),
      isNot(ouvindo),
      reason: 'a tradução tocando se dizia a gravação deles',
    );
    closeTheRoom(container);
  });

  testWidgets('a bead tapped before any verdict reads her «ouvindo a gravação '
      'de vocês…» while its frase plays, with its translation on the tablet', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await umaFraseContada(tester, harness);
    expect(
      container.read(salaSessionProvider).btTrechos.first.retroPath,
      isNotNull,
    );

    container.read(salaSessionProvider.notifier).ouvirAConta(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btTrechoTocando, isTrue);
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason: 'a conta tocava a tradução sob o convite a gravar',
    );
    closeTheRoom(container);
  });

  testWidgets('once a bead\'s frase ends before any verdict, the part it held '
      'reads her «pausado», not «ouvindo»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await umaFraseContada(tester, harness);
    harness.playback.at = s(5.0);
    await tester.pump(passaDoCursor);
    expect(rotuloDoCirculo(tester), ouvindo);

    container.read(salaSessionProvider.notifier).ouvirAConta(0);
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipPausada, isTrue);
    expect(
      rotuloDoCirculo(tester),
      pausado,
      reason: 'o círculo seguia dizendo ouvindo com nada tocando',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict a bead reads her «ouvindo a gravação de '
      'vocês…» while its frase plays, and the circle\'s own line once it '
      'ends', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await umaFraseConferida(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase traduzida de novo pousar',
      () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);

    notifier.ouvirAConta(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo,
      isNotNull,
    );
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason: 'a conta tocava a tradução sob o convite a gravar',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      rotuloDoCirculo(tester),
      'Tocar para gravar a tradução de novo',
      reason: 'o círculo seguia dizendo ouvindo com nada tocando',
    );
    closeTheRoom(container);
  });

  testWidgets('a clip held with no pause standing reads her «pausado», not '
      'the invitation to record', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    await tocar(tester, pausar);

    expect(
      rotuloDoCirculo(tester),
      pausado,
      reason: 'o círculo seguia convidando a gravar com a gravação parada',
    );
    expect(container.read(salaSessionProvider).btCortado, isFalse);
    closeTheRoom(container);
  });

  testWidgets('the end of the recording reads her «fim da gravação», not the '
      'invitation to record', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipEnded, isTrue);
    expect(
      rotuloDoCirculo(tester),
      fimDaGravacao,
      reason: 'o círculo seguia convidando a gravar no fim da gravação',
    );
    closeTheRoom(container);
  });

  testWidgets('a recording made at the end still offers to record again, not '
      'the end of the recording', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, fimDaGravacao);
    await tocar(tester, fimDaGravacao);
    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    await tocar(tester, terminar);
    await waitFor(
      'a sala recusar a frase',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(container.read(salaSessionProvider).btClipEnded, isTrue);
    expect(
      rotuloDoCirculo(tester),
      'Tocar para gravar a tradução de novo',
      reason: 'a gravação feita no fim passava a dizer que a gravação acabou',
    );
    closeTheRoom(container);
  });

  testWidgets('a pause standing at the end of the recording still reads «fim '
      'da gravação», not the pause hint', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, fimDaGravacao);

    final state = container.read(salaSessionProvider);
    expect(state.btCortado, isTrue);
    expect(state.btClipEnded, isTrue);
    expect(
      rotuloDoCirculo(tester),
      fimDaGravacao,
      reason: 'a pausa no fim da gravação trocava a frase dela pela da pausa',
    );
    closeTheRoom(container);
  });

  testWidgets('an english room is told the end of the recording in english, '
      'not in portuguese', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      rotuloDoCirculo(tester),
      'end of the recording',
      reason: 'o rótulo do fim da gravação ficava em português',
    );
    closeTheRoom(container);
  });

  testWidgets('a clip held before anything was heard reads her «pausado», not '
      'listen first', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = Duration.zero;

    await tocar(tester, pausar);

    final state = container.read(salaSessionProvider);
    expect(state.btClipPausada, isTrue);
    expect(state.nothingHeardSinceCursor, isTrue);
    expect(
      rotuloDoCirculo(tester),
      'pausado — toque no círculo para marcar onde a frase acaba',
      reason:
          'a gravação parada no cursor dizia ouvir primeiro, e o toque já '
          'marca a pausa',
    );
    closeTheRoom(container);
  });

  testWidgets('a tap on a clip held at the cursor places her pausa 0.2 s past '
      'it, not nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = Duration.zero;
    await tocar(tester, pausar);

    await tocarOCirculo(tester);

    expect(
      pausa(container),
      s(0.2),
      reason: 'o toque no cursor segurava a gravação e não punha pausa',
    );
    await traduzirEConfirmar(tester);
    expect(harness.room.chunkSpans, ['0-200']);
    closeTheRoom(container);
  });

  testWidgets('a tap with the head behind the cursor places her pausa 0.2 s '
      'past the cursor, never at the head', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(4.0);
    await tester.pump(passaDoCursor);
    await tocarOCirculo(tester);
    await traduzirEConfirmar(tester);
    expect(harness.room.chunkSpans, ['0-4000']);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);
    expect(container.read(salaSessionProvider).btClipRodando, isTrue);

    await tocarOCirculo(tester);
    await traduzirEConfirmar(tester);

    expect(
      harness.room.chunkSpans,
      ['0-4000', '4000-4200'],
      reason: 'o toque atrás do cursor segurava a gravação e não contava nada',
    );
    closeTheRoom(container);
  });

  testWidgets('a tap behind a cursor with less than 0.2 s of the part after it '
      'places no pausa, not a sliver', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(9.9);
    await tester.pump(passaDoCursor);
    await tocarOCirculo(tester);
    await traduzirEConfirmar(tester);
    expect(harness.room.chunkSpans, ['0-9900']);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    await tocarOCirculo(tester);

    expect(container.read(salaSessionProvider).btCortado, isFalse);
    await traduzirEConfirmar(tester);
    expect(
      harness.room.chunkSpans,
      ['0-9900'],
      reason: 'o piso passava do fim da parte e mandava uma frase de 0,1 s',
    );
    closeTheRoom(container);
  });

  testWidgets('the end of a part that another follows plays on under her '
      '«ouvindo a gravação de vocês…», not the invitation to record', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason:
          'o fim de uma parte com outra depois parava calado e convidava a gravar',
    );
    final state = container.read(salaSessionProvider);
    expect(state.btClipRodando, isTrue);
    expect(state.btClipEnded, isFalse);
    closeTheRoom(container);
  });

  testWidgets('the last part, reached by playing on, still ends at her «fim '
      'da gravação»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      rotuloDoCirculo(tester),
      fimDaGravacao,
      reason:
          'a última parte, alcançada sem toque, não dizia o fim da gravação',
    );
    expect(container.read(salaSessionProvider).btClipRodando, isFalse);
    closeTheRoom(container);
  });

  testWidgets('a part told to its end and heard whole again after the verdict '
      'sent them back to it reads her «pausado», not listen first', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await deVoltaAParteContadaAteOFim(tester, harness);
    final tocadas = harness.playback.played.length;

    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.playback.played,
      hasLength(tocadas),
      reason: 'a parte que o veredito mandou ouvir seguia para a próxima',
    );
    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue);
    expect(state.btParteFronteira, isTrue);
    expect(state.nothingHeardSinceCursor, isTrue);
    expect(
      rotuloDoCirculo(tester),
      pausado,
      reason:
          'a parte que o veredito mandou ouvir, ouvida inteira, seguia dizendo '
          'ouvir primeiro',
    );
    closeTheRoom(container);
  });

  testWidgets('the part the verdict sent them back to reads her «ouvindo a '
      'gravação de vocês…» while it plays, not listen first', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await deVoltaAParteContadaAteOFim(tester, harness);

    harness.playback.at = s(6.0);
    await tester.pump(passaDoCursor);

    final state = container.read(salaSessionProvider);
    expect(state.btClipRodando, isTrue);
    expect(state.nothingHeardSinceCursor, isTrue);
    expect(
      rotuloDoCirculo(tester),
      ouvindo,
      reason:
          'a parte que o veredito mandou ouvir, tocando, dizia ouvir primeiro',
    );
    closeTheRoom(container);
  });
}

Future<ProviderContainer> umaFraseContada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarComAFala(tester, harness, umaLacunaAos3);
  harness.playback.at = s(3.0);
  await tester.pump(passaDoCursor);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await waitFor(
    'a frase pousar',
    () => container.read(salaSessionProvider).btTrechos.isNotEmpty,
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  return container;
}

Future<ProviderContainer> umaFraseConferida(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await umaFraseContada(tester, harness);
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
  harness.room.verdictChecked = true;
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  return container;
}

Future<ProviderContainer> deVoltaAParteContadaAteOFim(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness);
  final primeira = harness.room.takeIds.first;
  await contarAteOFimDaParte(tester, harness);
  await contarAteOFimDaParte(tester, harness);
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
  harness.room
    ..verdictChecked = false
    ..verdictUnheardTakeIds = [primeira];
  await tester.tap(byLabel(conferir));
  await tester.pump(const Duration(milliseconds: 600));
  return container;
}
