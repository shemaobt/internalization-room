import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';

void main() {
  test('a clip that cannot be opened says so, and does not pass for heard', () async {
    final playback = PlaybackRepository(
      start: (_) async => throw const FormatException('arquivo corrompido'),
    );
    addTearDown(playback.dispose);
    final failed = playback.failures.first;
    var heard = false;
    playback.completions.listen((_) => heard = true);

    await playback.play('/uma/tomada/estragada.m4a');

    await expectLater(failed.timeout(const Duration(seconds: 2)), completes,
        reason: 'o ensaio e o retro só saem pelo fim da reprodução — sem aviso nenhum, '
            'uma tomada estragada tranca a tela sem gesto de saída');
    expect(heard, isFalse,
        reason: 'e o aviso não pode ser "terminou": o retro abre o terminei justamente '
            'quando o ensaio chega ao fim, e nada teria tocado');
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
