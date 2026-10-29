import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show passaDoCursor, pausar;
import 'the_pause_snaps_to_silence_test.dart' show entrarComAFala, s;

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
}
