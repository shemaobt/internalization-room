import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';

void _nada(_Duplo _) {}

PlaybackRepository _umRepositorioSobre(_Duplo tocador) {
  final novo = PlaybackRepository(newPlayer: () => tocador);
  addTearDown(novo.dispose);
  return novo;
}

/// The window the defect lives in is the load itself, not the gesture before it: the
/// hold has to arrive with the file already on its way in.
Future<void> _oLoadNoAr(_Duplo tocador, String qual) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!tocador.carregados.contains(qual)) {
    if (DateTime.now().isAfter(limite)) {
      fail('esperei 5s e o load de $qual não entrou no ar');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

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

    test('a clip asked for from a place opens there', () async {
      await playback.play('/o/clipe.m4a', from: const Duration(seconds: 30));

      expect(feitos.single.iniciais, [const Duration(seconds: 30)],
          reason: 'a retro retomada pede a parte a partir do chão já contado, e '
              'a posição tem de valer no instante em que o arquivo abre — '
              'mandar tocar e só depois pular deixa o começo do ensaio no ar');
      expect(playback.position, const Duration(seconds: 30),
          reason: 'e a posição segue contada do começo do arquivo: cortarTrecho '
              'compara esta leitura com o cursor');
      expect(feitos.single.tocando, isTrue);
    });

    test('duas medidas ao mesmo tempo dão a duração de cada arquivo', () async {
      playback = umRepositorio((duplo) {
        duplo.porArquivo['/a.m4a'] = const Duration(seconds: 4);
        duplo.porArquivo['/b.m4a'] = const Duration(seconds: 11);
        duplo.segurados['/a.m4a'] = Completer<void>();
      });

      final a = playback.howLong('/a.m4a');
      final b = playback.howLong('/b.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final medidor = feitos.single;
      expect(medidor.carregados, ['/a.m4a'],
          reason: 'o segundo pedido espera a vez: um AudioPlayer tem uma fonte '
              'só, e carregar por cima tira o arquivo das mãos de quem '
              'perguntou primeiro');

      medidor.segurados['/a.m4a']!.complete();

      expect(await a, const Duration(seconds: 4));
      expect(await b, const Duration(seconds: 11),
          reason: 'cada pergunta recebe a duração do arquivo que ela nomeou — a '
              'retomada dispara duas destas sem esperar nenhuma, e a primeira '
              'respondia com o tamanho da segunda, ou com nada');
      expect(medidor.carregados, ['/a.m4a', '/b.m4a']);
      expect(medidor.sobrepos, isFalse,
          reason: 'e nunca há dois carregamentos abertos no mesmo tocador');
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
      expect(feitos.single.carregados.last, '/o/clipe.m4a');

      await playback.pause();
      expect(feitos.single.tocando, isFalse);
      await playback.stop();
      expect(playback.playingLength, isNull);
    });
  });

  test('a dispose that lands while a load is still in the air writes nothing '
      'after closing', () async {
    final tocador = _Duplo();
    final playback = PlaybackRepository(newPlayer: () => tocador);
    final anunciadas = <void>[];
    playback.openings.listen(anunciadas.add);
    tocador.segurados['/parte-1.m4a'] = Completer<void>();

    final abrindo = playback.play('/parte-1.m4a');
    await _oLoadNoAr(tocador, '/parte-1.m4a');

    await playback.dispose();
    tocador.segurados['/parte-1.m4a']!.complete();
    await abrindo;

    expect(anunciadas, isEmpty,
        reason:
            'o repositório já se fechou; o load que assenta atrás dele não '
            'pode escrever numa fila de eventos fechada');
  });

  test('the same is true of the slice a stretch plays', () async {
    final tocador = _Duplo();
    final playback = PlaybackRepository(newPlayer: () => tocador);
    final falhas = <void>[];
    playback.failures.listen(falhas.add);
    tocador.segurados['/parte-1.m4a'] = Completer<void>();

    final abrindo = playback.playRange(
      '/parte-1.m4a',
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    );
    await _oLoadNoAr(tocador, '/parte-1.m4a');

    await playback.dispose();
    tocador.segurados['/parte-1.m4a']!.complete();
    await abrindo;

    expect(falhas, isEmpty,
        reason:
            'o repositório já se fechou; o catch da fatia não pode escrever '
            'numa fila de eventos fechada');
  });

  test('pausing a player that never opened is not an error', () async {
    final playback = PlaybackRepository(start: (_) async {});
    addTearDown(playback.dispose);

    await playback.pause();
    await playback.resume();
    await playback.stop();
  });

  group('segurar o clipe enquanto ele ainda abre', () {
    late _Duplo tocador;
    late PlaybackRepository playback;

    setUp(() {
      tocador = _Duplo();
      playback = _umRepositorioSobre(tocador);
    });

    test('a pausa pedida durante o load vence o play que vinha atrás', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.pause();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(tocador.tocando, isFalse,
          reason: 'a equipe segurou o clipe e o load tocou por cima: a pausa '
              'não sai do lugar num player que ainda não toca, e o play que '
              'vem atrás do load a apaga sem deixar rasto');
    });

    test('o stop pedido durante o load também vence', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.stop();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(tocador.tocando, isFalse);
    });

    test('a abertura segurada ainda se anuncia, com a medida', () async {
      final anunciadas = <void>[];
      playback.openings.listen(anunciadas.add);
      tocador.segurados['/parte-1.m4a'] = Completer<void>();

      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');
      await playback.pause();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;
      await Future<void>.delayed(Duration.zero);

      expect(anunciadas, hasLength(1),
          reason: 'quem espera a abertura — o teto da escuta e a medida da '
              'parte no ar — fica encalhado se um clipe segurado nunca se '
              'anuncia');
      expect(playback.playingLength, const Duration(seconds: 30));
    });

    test('o stop durante o load não deixa a medida para trás', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.stop();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(playback.playingLength, isNull,
          reason: 'o stop limpa o que o clipe media, e o load que termina atrás '
              'dele não pode escrever de volta: o teto do clipe seguinte sai '
              'daqui, e sairia do comprimento de um clipe que nunca tocou');
    });

    test('a pausa durante o load guarda a medida, que é o que o teto conta',
        () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.pause();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(playback.playingLength, const Duration(seconds: 30),
          reason: 'uma pausa deixa o clipe aberto: é a mesma parte que o '
              'próximo toque retoma, e o teto conta o que falta dela');
    });

    test('sem nenhum hold o clipe toca, como sempre tocou', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(tocador.tocando, isTrue);
    });

    test('o load que o nosso próprio stop cortou não chega como falha',
        () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);
      tocador.cortaOLoadNoStop = true;
      tocador.segurados['/parte-1.m4a'] = Completer<void>();

      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');
      await playback.stop();
      await abrindo;
      await Future<void>.delayed(Duration.zero);

      expect(falhas, isEmpty,
          reason: 'o stop é nosso: lido como o clipe não tocando, nunca como o '
              'tablet sem conseguir tocar a voz da equipe — que chama uma '
              'pessoa e para a sala por cima de um gesto comum');
    });

    test('um load interrompido sem hold nenhum continua sendo falha', () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);
      tocador.recusa = PlayerInterruptedException('a sessão caiu');

      await playback.play('/parte-1.m4a');
      await Future<void>.delayed(Duration.zero);

      expect(falhas, hasLength(1),
          reason: 'só o nosso próprio stop é lido como o clipe não tocando. '
              'Sem hold nenhum, um load que o aparelho interrompeu é o tablet '
              'sem conseguir tocar a voz da equipe, e isso chama uma pessoa');
    });

    test('depois de um hold durante o load, o próximo play toca', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');
      await playback.pause();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      await playback.play('/parte-2.m4a');

      expect(tocador.tocando, isTrue,
          reason: 'a espera vale para a abertura que o hold apanhou, não para '
              'o próximo gesto da equipe');
      expect(tocador.carregados, ['/parte-1.m4a', '/parte-2.m4a']);
    });

    test('o mesmo vale para a fatia que um trecho toca', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.playRange(
        '/parte-1.m4a',
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      );
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.pause();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(tocador.tocando, isFalse);
    });
  });

  group('o player responde na ordem em que a equipe pediu', () {
    late _Duplo tocador;
    late PlaybackRepository playback;

    setUp(() {
      tocador = _Duplo();
      playback = _umRepositorioSobre(tocador);
    });

    test('um resume desfaz o hold dado enquanto o clipe ainda abria', () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.pause();
      await playback.resume();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(tocador.tocando, isTrue,
          reason: 'o último gesto da equipe foi um resume, e é ele que manda: '
              'a espera que o hold abriu não sobrevive ao gesto que a desfez. '
              'Pino da regra, não de uma regressão: isto é verde antes e '
              'depois do conserto, porque o som nunca dependeu do play de '
              'cauda — o play do próprio resume já punha o clipe a tocar '
              'assim que a fonte ficasse pronta. O que o conserto acerta é o '
              'repositório dizer o mesmo que o player faz');
      expect(playback.playingLength, const Duration(seconds: 30),
          reason: 'e o clipe fica aberto, com a medida de que o teto da escuta '
              'e a medida da parte no ar saem');
    });

    test('o hold durante o load continua valendo quando nada o desfaz',
        () async {
      tocador.segurados['/parte-1.m4a'] = Completer<void>();
      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.pause();
      tocador.segurados['/parte-1.m4a']!.complete();
      await abrindo;

      expect(tocador.tocando, isFalse,
          reason: 'o resume é que desfaz o hold, e ninguém pediu um');

      await playback.resume();

      expect(tocador.tocando, isTrue);
      expect(tocador.carregados, ['/parte-1.m4a'],
          reason: 'o clipe já está aberto: um resume põe a soar o que está '
              'na mão, nunca manda abrir a fonte outra vez');
    });

    test('um play por cima de um play cala o primeiro em vez de chamar uma '
        'pessoa', () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);
      final anunciadas = <void>[];
      playback.openings.listen(anunciadas.add);
      tocador.cortaOLoadNoStop = true;
      tocador.porArquivo['/parte-1.m4a'] = const Duration(seconds: 30);
      tocador.porArquivo['/parte-2.m4a'] = const Duration(seconds: 12);
      tocador.segurados['/parte-1.m4a'] = Completer<void>();

      final primeira = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.play('/parte-2.m4a');
      await primeira;
      await Future<void>.delayed(Duration.zero);

      expect(falhas, isEmpty,
          reason: 'quem cortou o load da primeira foi a segunda abertura, '
              'nossa: isso é o clipe não tocando, nunca o tablet sem conseguir '
              'tocar a voz da equipe — que chama uma pessoa por cima de um som '
              'que a própria equipe pediu');
      expect(tocador.tocando, isTrue);
      expect(anunciadas, hasLength(1),
          reason: 'só o clipe que ficou de pé se anuncia: a abertura '
              'atropelada não tem medida nem teto a dar a ninguém');
      expect(playback.playingLength, const Duration(seconds: 12),
          reason: 'e a medida é a da segunda, que é a que está no ar');
    });

    test('o mesmo vale para duas fatias de trecho seguidas', () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);
      final anunciadas = <void>[];
      playback.openings.listen(anunciadas.add);
      tocador.cortaOLoadNoStop = true;
      tocador.segurados['/parte-1.m4a'] = Completer<void>();

      final primeira = playback.playRange(
        '/parte-1.m4a',
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      );
      await _oLoadNoAr(tocador, '/parte-1.m4a');

      await playback.playRange(
        '/parte-2.m4a',
        const Duration(seconds: 3),
        const Duration(seconds: 4),
      );
      await primeira;
      await Future<void>.delayed(Duration.zero);

      expect(falhas, isEmpty);
      expect(tocador.tocando, isTrue);
      expect(anunciadas, hasLength(1));
    });

    test('um resume depois de um stop não ressuscita o clipe que ele parou',
        () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);
      final anunciadas = <void>[];
      playback.openings.listen(anunciadas.add);
      tocador.segurados['/parte-1.m4a'] = Completer<void>();

      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');
      await playback.stop();
      await playback.resume();
      tocador.segurados['/parte-1.m4a']!
          .completeError(PlayerInterruptedException('parado'));
      await abrindo;
      await Future<void>.delayed(Duration.zero);

      expect(falhas, isEmpty,
          reason: 'quem cortou o load foi o nosso próprio stop, e um resume '
              'dado depois dele não transforma o gesto da equipe numa falha '
              'do tablet — que chama uma pessoa e para a sala');
      expect(anunciadas, isEmpty,
          reason: 'um resume desfaz uma pausa, não um stop: o clipe parado '
              'não volta a se anunciar, e a medida que o stop apagou não '
              'pode ser escrita de volta pelo load que assenta atrás dele');
      expect(playback.playingLength, isNull);
    });

    test('depois de um resume, a interrupção do aparelho volta a ser falha',
        () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);
      tocador.segurados['/parte-1.m4a'] = Completer<void>();

      final abrindo = playback.play('/parte-1.m4a');
      await _oLoadNoAr(tocador, '/parte-1.m4a');
      await playback.pause();
      await playback.resume();
      tocador.segurados['/parte-1.m4a']!
          .completeError(PlayerInterruptedException('a sessão caiu'));
      await abrindo;
      await Future<void>.delayed(Duration.zero);

      expect(falhas, hasLength(1),
          reason: 'o hold foi desfeito e nenhum gesto nosso cortou este load: '
              'o que sobra é o tablet sem conseguir tocar a voz da equipe, e '
              'isso chama uma pessoa. A contagem antiga engolia esta, porque '
              'o hold que o resume desfez ficava marcado para sempre');
    });

    test('um resume num clipe que nunca abriu não faz nada', () async {
      final falhas = <void>[];
      playback.failures.listen(falhas.add);

      await playback.resume();
      await Future<void>.delayed(Duration.zero);

      expect(tocador.tocando, isFalse,
          reason: 'não há clipe nenhum para voltar a soar');
      expect(tocador.carregados, isEmpty);
      expect(falhas, isEmpty);
    });
  });
}

/// A stand-in for the platform player, so the tests can watch what the repository does
/// with it — which player it loads a file into, and what it leaves behind.
class _Duplo extends Fake implements AudioPlayer {
  final List<String> carregados = [];

  /// Where each load was told to open. The position a real player answers with is the one
  /// it was given at load, so the double sets [at] from it too.
  final List<Duration?> iniciais = [];
  final _states = StreamController<PlayerState>.broadcast();
  Duration? length = const Duration(seconds: 30);
  /// So a test can give the clip in the air one length and the file being asked about
  /// another — without that, a probe on the wrong player is indistinguishable.
  final Map<String, Duration> porArquivo = {};
  Duration at = Duration.zero;
  bool tocando = false;
  bool descartado = false;
  Object? recusa;

  /// Loads this double holds open, by file. The length still comes from [porArquivo], so
  /// a held file and a free one are answered by the same rule.
  final Map<String, Completer<void>> segurados = {};

  /// Whether a load ever started while another was still open on this player.
  ///
  /// A real [AudioPlayer] has one source: the second load replaces the first, and the
  /// first call comes back answering for the wrong file or for nothing. The double cannot
  /// reproduce that corruption, so it records the overlap that causes it.
  bool sobrepos = false;
  int _abertos = 0;

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
    if (_abertos > 0) sobrepos = true;
    _abertos++;
    carregados.add(filePath);
    iniciais.add(initialPosition);
    try {
      await segurados[filePath]?.future;
    } finally {
      _abertos--;
    }
    at = initialPosition ?? Duration.zero;
    return porArquivo[filePath] ?? length;
  }

  /// Which file a clipped source is a slice of. A real player has one source per file,
  /// so two slices of two different recordings are two different loads — keyed as one,
  /// the double could not hold one of them open while the other went free.
  ///
  /// It throws rather than falling back to one shared key: a fallback would put that
  /// collision back silently, the day something hands this double another source.
  String _arquivoDe(AudioSource source) => source is ClippingAudioSource
      ? source.child.uri.toFilePath()
      : throw UnsupportedError('o dublê só sabe recortar uma fonte de arquivo');

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    final arquivo = _arquivoDe(source);
    carregados.add(arquivo);
    if (_abertos > 0) sobrepos = true;
    _abertos++;
    try {
      await segurados[arquivo]?.future;
    } finally {
      _abertos--;
    }
    return porArquivo[arquivo] ?? length;
  }

  @override
  Future<void> play() async {
    // As the real one does: just_audio's `play()` opens with `if (playing) return;`, so
    // a play issued over a player already playing is not a second sound. Without this,
    // a double answers "it played" for a repository that said nothing at all.
    if (tocando) return;
    tocando = true;
  }

  /// What a real player does to a load its own deactivation cut short: just_audio
  /// deactivates the platform at once and the pending load throws.
  bool cortaOLoadNoStop = false;

  @override
  Future<void> stop() async {
    tocando = false;
    // Only a load already in the air: the open's own stop runs before the load starts,
    // and a real player has nothing to interrupt there.
    if (!cortaOLoadNoStop || _abertos == 0) return;
    for (final segurado in segurados.values) {
      if (!segurado.isCompleted) {
        segurado.completeError(PlayerInterruptedException('parado'));
      }
    }
  }

  @override
  Future<void> pause() async {
    tocando = false;
  }

  @override
  Future<void> dispose() async => descartado = true;
}
