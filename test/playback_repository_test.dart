import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';

void main() {
  test('a clip that cannot be opened still ends the wait', () async {
    final playback = PlaybackRepository(
      start: (_) async => throw const FormatException('arquivo corrompido'),
    );
    addTearDown(playback.dispose);
    final ended = playback.completions.first;

    await playback.play('/uma/tomada/estragada.m4a');

    await expectLater(ended.timeout(const Duration(seconds: 2)), completes,
        reason: 'o ensaio e o retro só saem pelo fim da reprodução — sem esse aviso, '
            'uma tomada estragada tranca a tela sem gesto nenhum de saída');
  });

  test('a clip that opens says nothing until it actually ends', () async {
    var ended = false;
    final playback = PlaybackRepository(start: (_) async {});
    addTearDown(playback.dispose);
    playback.completions.listen((_) => ended = true);

    await playback.play('/uma/tomada/boa.m4a');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(ended, isFalse,
        reason: 'anunciar o fim na abertura pularia o clipe inteiro');
  });

  test('pausing a player that never opened is not an error', () async {
    final playback = PlaybackRepository(start: (_) async {});
    addTearDown(playback.dispose);

    await playback.pause();
    await playback.resume();
    await playback.stop();
  });
}
