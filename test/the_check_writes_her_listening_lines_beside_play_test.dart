import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show contarAteOFimDaParte, passaDoCursor, pausar, tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show
        entrarComAFala,
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
}
