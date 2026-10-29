import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_resumed_back_translation_circle_opens_the_microphone_test.dart'
    show reopenedInto;
import 'fakes.dart';
import 'the_check_circle_says_hers_when_held_and_at_the_end_test.dart'
    show umaFraseConferida;
import 'the_check_frase_rows_are_drawn_as_hers_test.dart' show voltaATraducao;
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show contarAteOFimDaParte, passaDoCursor, pausar, tocar;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;
import 'the_pause_snaps_to_silence_test.dart'
    show
        entrarComAFala,
        ouvirAPausa,
        pausarAos,
        rotuloDoCirculo,
        s,
        tocarOCirculo,
        umaLacunaAos3;

Finder naTela(String linha) =>
    find.descendant(of: find.byType(RetroView), matching: find.text(linha));

void main() {
  testWidgets('a part playing on the check writes «ouvindo a gravação de '
      'vocês…» and its place beside play, not only to VoiceOver', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    final linha = naTela(
      'ouvindo a gravação de vocês… — parte 1 · 0:02 / 0:10',
    );
    expect(
      linha,
      findsOneWidget,
      reason: 'a escuta só existia como rótulo do círculo para o VoiceOver',
    );
    final play = tester.getRect(byLabel(pausar));
    final texto = tester.getRect(linha);
    expect(
      texto.left,
      greaterThan(play.right),
      reason: 'a linha não ficava ao lado do play',
    );
    expect(texto.top, lessThan(play.bottom));
    expect(texto.bottom, greaterThan(play.top));
    closeTheRoom(container);
  });

  testWidgets('a part paused with play writes «pausado — toque no círculo…» '
      'and where it stopped, not a bare button', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    await tocar(tester, pausar);

    expect(container.read(salaSessionProvider).btClipPausada, isTrue);
    expect(
      naTela(
        'pausado — toque no círculo para marcar onde a frase acaba — '
        'parte 1 · 0:02 / 0:10',
      ),
      findsOneWidget,
      reason: 'a parte parada não dizia nada ao lado do play',
    );
    closeTheRoom(container);
  });

  testWidgets('a pause marked on a silence writes «a pausa ficou aqui…» '
      'beside play, where the circle only said it to VoiceOver', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    expect(
      rotuloDoCirculo(tester),
      'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo '
      'para traduzir',
    );
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.textContaining(
          'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no '
          'círculo para traduzir — parte 1 · ',
        ),
      ),
      findsOneWidget,
      reason: 'a pausa marcada não dizia onde ficou ao lado do play',
    );
    closeTheRoom(container);
  });

  testWidgets('«ouvir a pausa» sounding over the held part keeps the part\'s '
      'place beside play, not a line with no place', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    await tocar(tester, ouvirAPausa);

    expect(container.read(salaSessionProvider).btCortado, isTrue);
    expect(harness.playback.sounding, isTrue);
    expect(
      naTela(
        'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo '
        'para traduzir — parte 1 · 0:04 / 0:10',
      ),
      findsOneWidget,
      reason: 'ouvir a pausa apagava o lugar da parte segurada embaixo',
    );
    closeTheRoom(container);
  });

  testWidgets('a pause with no silence to rest on writes «a pausa ficou no '
      'toque…», not the hint to move it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    await pausarAos(tester, harness, s(4.2));

    expect(
      rotuloDoCirculo(tester),
      'a pausa ficou no toque — toquem no círculo para traduzir',
    );
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.textContaining(
          'a pausa ficou no toque — toquem no círculo para traduzir — '
          'parte 1 · ',
        ),
      ),
      findsOneWidget,
      reason: 'a pausa no toque mandava ajustar uma pausa que não se ajusta',
    );
    closeTheRoom(container);
  });

  testWidgets('the pause line and its place stay beside play while the '
      'translation is recorded, not only until the microphone opens', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    await pausarAos(tester, harness, s(4.2));

    await tocarOCirculo(tester);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.textContaining(
          'a pausa ficou no toque — toquem no círculo para traduzir — '
          'parte 1 · ',
        ),
      ),
      findsOneWidget,
      reason: 'a linha perdia o lugar da pausa quando o microfone abria',
    );
    closeTheRoom(container);
  });

  testWidgets('the recording told to its end writes «fim da gravação» '
      'beside play, with no place left over', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    await contarAteOFimDaParte(tester, harness);

    expect(container.read(salaSessionProvider).btClipEnded, isTrue);
    expect(
      naTela('fim da gravação'),
      findsOneWidget,
      reason: 'o fim da gravação só existia para o VoiceOver',
    );
    closeTheRoom(container);
  });

  testWidgets('a bead replaying the recording after its end writes «ouvindo a '
      'gravação de vocês…», not the end', (tester) async {
    final (harness, container) = await reopenedInto(tester, toldUpTo: 5000);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(naTela('fim da gravação'), findsOneWidget);

    container.read(salaSessionProvider.notifier).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue);
    expect(state.btTrechoTocando, isTrue);
    expect(
      naTela('ouvindo a gravação de vocês…'),
      findsOneWidget,
      reason: 'a conta tocando a gravação no fim se dizia o fim da gravação',
    );
    harness.playback.stopWalking();
    closeTheRoom(container);
  });

  testWidgets('while a sentence waits to be recorded again nothing beside '
      'play asks for the circle, which is that sentence\'s microphone', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(naTela('gravem a frase inteira'), findsOneWidget);

    for (final linha in [
      'fim da gravação',
      'pausado — toque no círculo',
      'a pausa ficou',
      'ouvindo a gravação de vocês…',
    ]) {
      expect(
        find.descendant(
          of: find.byType(RetroView),
          matching: find.textContaining(linha),
        ),
        findsNothing,
        reason: 'a linha do play falava por cima da regravação: $linha',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('a sentence heard before it is recorded again leaves its place '
      'beside play, the clock alone, not an empty row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(naTela('gravem a frase inteira'), findsOneWidget);
    expect(harness.playback.sounding, isFalse);

    expect(
      naTela('parte 2 · 0:04 / 0:10'),
      findsOneWidget,
      reason: 'a regravação sem som apagava a linha inteira, relógio junto',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence being told again with nothing sounding leaves its '
      'place beside play, the clock alone', (tester) async {
    final (harness, container) = await reopenedInto(tester, toldUpTo: 5000);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    container.read(salaSessionProvider.notifier).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.stopWalking();
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(salaSessionProvider);
    expect(state.btTrechoTraduzidoDeNovo, isNotNull);
    expect(state.btTrechoTocando, isFalse);
    expect(
      naTela('parte 1 · 0:05 / 0:30'),
      findsOneWidget,
      reason: 'a frase traduzida de novo sem som apagava a linha do play',
    );
    closeTheRoom(container);
  });

  testWidgets('the english room writes her english lines beside play, '
      'not the portuguese ones', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    expect(
      naTela('listening to your recording… — part 1 · 0:02 / 0:10'),
      findsOneWidget,
      reason: 'a sala em inglês escrevia a escuta em português',
    );

    await tocar(tester, 'Pause');

    expect(
      naTela(
        'paused — tap the circle to mark where the sentence ends — '
        'part 1 · 0:02 / 0:10',
      ),
      findsOneWidget,
      reason: 'a sala em inglês escrevia a pausa em português',
    );
    closeTheRoom(container);
  });

  testWidgets('a passage checked clean writes no listening line beside play, '
      'where the circle no longer opens a sentence', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await umaFraseConferida(tester, harness);
    await tester.pump(const Duration(milliseconds: 800));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    for (final linha in [
      'fim da gravação',
      'pausado — toque no círculo',
      'a pausa ficou',
      'ouvindo a gravação de vocês…',
    ]) {
      expect(
        find.descendant(
          of: find.byType(RetroView),
          matching: find.textContaining(linha),
        ),
        findsNothing,
        reason:
            'o conferido mandava tocar num círculo que não responde: $linha',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('the part the room numbers 3 writes «parte 3» beside play, not '
      'its place in the row of parts', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback
      ..length = s(10)
      ..measured = s(10);
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: []),
      partes: [1, 3],
    );
    final partes = container.read(salaSessionProvider).partes;
    await waitFor(
      'a primeira parte no ar',
      () => harness.playback.played.lastOrNull == partes[0].path,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    harness.playback
      ..at = s(10)
      ..finishPlayback();
    await waitFor(
      'a segunda parte no ar',
      () =>
          harness.playback.played.last == partes[1].path &&
          harness.playback.sounding,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    expect(
      naTela('ouvindo a gravação de vocês… — parte 3 · 0:02 / 0:10'),
      findsOneWidget,
      reason:
          'a parte que a sala numera 3 se dizia «parte 2», o lugar dela na '
          'fileira',
    );
    closeTheRoom(container);
  });

  testWidgets('the first listen writes «parte 3» for the part the room '
      'numbers 3 too, not its place in the row', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback
      ..length = s(10)
      ..measured = s(10);
    harness.room.listeningUnheardTakeIds = ['gravacao-1', 'gravacao-3'];
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: []),
      partes: [1, 3],
    );
    final partes = container.read(salaSessionProvider).partes;
    await waitFor(
      'a primeira parte no ar',
      () => harness.playback.played.lastOrNull == partes[0].path,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    harness.playback
      ..at = s(10)
      ..finishPlayback();
    await waitFor(
      'a segunda parte no ar',
      () =>
          harness.playback.played.last == partes[1].path &&
          harness.playback.sounding,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    harness.playback.at = s(2.0);
    await tester.pump(passaDoCursor);

    expect(container.read(salaSessionProvider).btSoOuvir, isTrue);
    expect(
      naTela('ouvindo a gravação de vocês… — parte 3 · 0:02 / 0:10'),
      findsOneWidget,
      reason: 'a primeira escuta dizia «parte 2» na parte que a sala numera 3',
    );
    closeTheRoom(container);
  });

  testWidgets('on the iPhone SE her longest line beside play keeps 16 points '
      'from the edge and grows its row, instead of running off or clipping', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(375, 667)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, umaLacunaAos3);
    await pausarAos(tester, harness, s(4.2));

    final linha = find.descendant(
      of: find.byType(RetroView),
      matching: find.textContaining(
        'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo '
        'para traduzir — parte 1 · ',
      ),
    );
    expect(linha, findsOneWidget);
    final paragrafo = tester.renderObject<RenderParagraph>(linha);
    expect(
      paragrafo.size.height,
      greaterThanOrEqualTo(
        paragrafo.getMaxIntrinsicHeight(paragrafo.size.width),
      ),
      reason: 'a fileira de 60 do play cortava a linha comprida',
    );
    final play = tester.getRect(byLabel('Ouvir'));
    final texto = tester.getRect(linha);
    expect(play.left, greaterThanOrEqualTo(16));
    expect(texto.left, greaterThan(play.right));
    expect(
      texto.right,
      lessThanOrEqualTo(375 - 16),
      reason: 'a linha encostava na borda direita do iPhone SE',
    );
    closeTheRoom(container);
  });
}
