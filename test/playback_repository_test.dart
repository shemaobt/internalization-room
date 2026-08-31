import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';

void _nada(_Duplo _) {}

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

  group('how long is this', () {
    late List<_Duplo> feitos;
    late PlaybackRepository playback;

    /// Every repository a test builds registers its own tear-off. Registering the one
    /// from `setUp` and then reassigning left the repository the test actually drives
    /// undisposed, with its controllers and its players still open.
    PlaybackRepository umRepositorio([void Function(_Duplo) afinando = _nada]) {
      final novo = PlaybackRepository(newPlayer: () {
        final duplo = _Duplo();
        afinando(duplo);
        feitos.add(duplo);
        return duplo;
      });
      addTearDown(novo.dispose);
      return novo;
    }

    setUp(() {
      feitos = [];
      playback = umRepositorio();
    });

    test('the room learns how long an audio is without playing it', () async {
      final quanto = await playback.howLong('/uma/gravacao.m4a');

      expect(quanto, const Duration(seconds: 30));
      expect(feitos.single.carregados, ['/uma/gravacao.m4a'],
          reason: 'a pergunta carrega o arquivo, que é como a duração se sabe');
      expect(feitos.single.tocando, isFalse,
          reason: 'e não sai som: perguntar não é ouvir, e a sala fala por cima '
              'de áudio que ninguém pediu');
    });

    test('asking in the middle of a playback does not interrupt it', () async {
      await playback.play('/o/clipe.m4a');
      final tocador = feitos.single;
      tocador.at = const Duration(seconds: 7);

      await playback.howLong('/outra/gravacao.m4a');

      expect(tocador.tocando, isTrue,
          reason: 'o que estava tocando continua tocando');
      expect(playback.position, const Duration(seconds: 7),
          reason: 'e do mesmo ponto — cortarTrecho lê esta posição direto para '
              'fechar um trecho');
      expect(tocador.carregados, ['/o/clipe.m4a'],
          reason: 'o player que toca não recebe o arquivo perguntado');
    });

    test('asking does not corrupt the measure of what is in the air', () async {
      // Two different lengths on purpose: the clip in the air is half a minute and the
      // file being asked about is four seconds. A probe on the playing player would
      // leave the room believing the rehearsal is four seconds long.
      playback = umRepositorio((duplo) =>
          duplo.porArquivo['/uma/gravacao/curta.m4a'] = const Duration(seconds: 4));
      await playback.play('/o/clipe.m4a');
      final doClipe = playback.playingLength;
      expect(doClipe, const Duration(seconds: 30));

      await playback.howLong('/uma/gravacao/curta.m4a');

      expect(playback.playingLength, doClipe,
          reason: 'esta é a régua da escuta: _fimDaParteMs sai daqui e '
              '_retroClipMs sai dele, e é o portão que impede a equipe de '
              'encerrar sem ter ouvido. Foi assim que um ensaio de três partes '
              'se reportou como uma parte só');
    });

    test('asking before any playback answers', () async {
      final quanto = await playback.howLong('/uma/gravacao.m4a');

      expect(quanto, const Duration(seconds: 30),
          reason: 'é o caso da retomada: a sonda roda antes de o primeiro '
              'clipe abrir');
      expect(playback.playingLength, isNull,
          reason: 'e não inventa um clipe no ar que não existe');
    });

    test('a file that is not there does not bring the room down', () async {
      playback = umRepositorio(
        (duplo) => duplo.recusa = const FormatException('sumiu'),
      );

      final quanto = await playback.howLong('/nao/existe.m4a');

      expect(quanto, isNull,
          reason: 'quem pergunta trata a ausência de resposta; derrubar a sala '
              'por um arquivo que sumiu é perder a passagem inteira');
    });

    test('the ordinary playback still answers as it always did', () async {
      await playback.play('/o/clipe.m4a');
      expect(feitos.single.tocando, isTrue);
      expect(playback.playingLength, const Duration(seconds: 30));

      await playback.playRange(
        '/o/clipe.m4a',
        Duration.zero,
        const Duration(seconds: 5),
      );
      expect(feitos.single.carregados.last, 'recorte');

      await playback.pause();
      expect(feitos.single.tocando, isFalse);
      await playback.stop();
      expect(playback.playingLength, isNull);
    });
  });

  test('pausing a player that never opened is not an error', () async {
    final playback = PlaybackRepository(start: (_) async {});
    addTearDown(playback.dispose);

    await playback.pause();
    await playback.resume();
    await playback.stop();
  });
}

/// A stand-in for the platform player, so the tests can watch what the repository does
/// with it — which player it loads a file into, and what it leaves behind.
class _Duplo extends Fake implements AudioPlayer {
  final List<String> carregados = [];
  final _states = StreamController<PlayerState>.broadcast();
  Duration? length = const Duration(seconds: 30);
  /// So a test can give the clip in the air one length and the file being asked about
  /// another — without that, a probe on the wrong player is indistinguishable.
  final Map<String, Duration> porArquivo = {};
  Duration at = Duration.zero;
  bool tocando = false;
  bool descartado = false;
  Object? recusa;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  ProcessingState get processingState => ProcessingState.ready;

  @override
  Duration get position => at;

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    final no = recusa;
    if (no != null) throw no;
    carregados.add(filePath);
    return porArquivo[filePath] ?? length;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    carregados.add('recorte');
    return length;
  }

  @override
  Future<void> play() async => tocando = true;

  @override
  Future<void> stop() async => tocando = false;

  @override
  Future<void> pause() async => tocando = false;

  @override
  Future<void> dispose() async => descartado = true;
}
