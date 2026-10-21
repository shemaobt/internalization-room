import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'o_take_pausa_test.dart' show pumpAoGravado;
import 'scenario_helpers.dart' show byLabel, settle;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        conferir,
        confirmar,
        contarAteOFimDaParte,
        entrarNaTraducao,
        fimDaGravacao,
        gravar,
        gravarATraducao,
        parte,
        ouvir,
        passaDoCursor,
        pausado,
        pausar,
        tesoura,
        tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show entrarComAFala, rotuloDoCirculo, s;

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
    await gravarATraducao(tester, circulo: fimDaGravacao);

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
    harness.recorder.returnsNothing = true;
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await gravarATraducao(tester, circulo: fimDaGravacao);

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

  testWidgets('a clip held before anything was heard still says to listen '
      'first, not «pausado»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = Duration.zero;

    await tocar(tester, pausar);

    expect(container.read(salaSessionProvider).btClipPausada, isTrue);
    expect(
      rotuloDoCirculo(tester),
      'Ouvir primeiro',
      reason: 'a gravação parada no cursor dizia pausado, sem nada ouvido',
    );
    closeTheRoom(container);
  });

  testWidgets('the end of a part that another follows is not the end of the '
      'recording', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btParteFronteira, isTrue);
    expect(
      rotuloDoCirculo(tester),
      gravar,
      reason: 'o fim de uma parte com outra depois dizia que a gravação acabou',
    );
    closeTheRoom(container);
  });

  testWidgets('the end of a part the verdict sent them back to is not the end '
      'of the recording while the next part is still offered', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    final primeira = harness.room.takeIds.first;
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, ouvir);
    await contarAteOFimDaParte(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [primeira];
    await tester.tap(byLabel(conferir));
    await tester.pump(const Duration(milliseconds: 600));

    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue);
    expect(state.btParteFronteira, isTrue);
    expect(
      rotuloDoCirculo(tester),
      'Ouvir primeiro',
      reason:
          'a parte que o veredito mandou ouvir dizia fim da gravação com a '
          'parte seguinte ainda oferecida',
    );
    closeTheRoom(container);
  });
}
