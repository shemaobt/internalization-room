import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

/// How long every part of the rehearsal lasts in these tests.
const _parteInteira = Duration(seconds: 30);

/// Where the reading head sits, read off the cord the team is looking at.
int cabeca(WidgetTester tester) =>
    tester.widget<RetroCord>(find.byType(RetroCord)).ouvidoMs;

/// The same head as a place on the cord — what the eye actually follows.
double naCorda(WidgetTester tester) {
  final cord = tester.widget<RetroCord>(find.byType(RetroCord));
  return cordFraction(
    atMs: cord.ouvidoMs,
    partes: cord.partes,
    fimDasPartes: cord.fimDasPartes,
    parteNoArMs: cord.parteNoArMs,
  );
}

SalaHarness _umEnsaioQueCorre() => SalaHarness(filaEmMemoria: true)
  ..playback.length = _parteInteira
  ..playback.measured = _parteInteira
  ..playback.walkWhilePlaying();

/// A team already in the retro, with the first part of the rehearsal in the air.
Future<ProviderContainer> retroTocando(
  WidgetTester tester,
  SalaHarness harness, {
  int partes = 1,
}) async {
  final container = harness.container();
  addTearDown(container.dispose);
  addTearDown(harness.playback.stopWalking);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  for (var parte = 0; parte < partes; parte++) {
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await letTheRehearsalReachTheRoom(tester);
  }
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

/// Throw the screen away with a part still in the air, and let the clock run on.
///
/// The room's own clip timers go with the container, as they do when the team leaves the
/// passage. What is left over after this is the cord's, and `flutter_test` fails the test
/// for it.
Future<void> sairDaSala(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.playback.stopWalking();
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await tester.pump();
}

/// A rehearsal that runs, with the room ready to answer *terminei* with a finding on the
/// last stretch the team told back.
SalaHarness _umAchadoNaParteDois() => _umEnsaioQueCorre()
  ..room.verdictChecked = false
  ..room.verdictFinding = BtFindingKind.missing
  ..room.verdictFindingSegmentId = 'trecho-4';

/// Cut the part in the air at [ate] and tell that stretch back.
Future<void> _contarAte(
  WidgetTester tester,
  SalaHarness harness,
  SalaSessionNotifier notifier,
  Duration ate,
) async {
  harness.playback.at = ate;
  notifier.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Where the stretch the analyst points at sits in part two, and what it therefore
/// occupies on the cord once part one's thirty seconds are behind it.
const _trechoDe = Duration(seconds: 6);
const _trechoAte = Duration(seconds: 9);
const _naCordaDe = 36000;
const _naCordaAte = 39000;

/// A team on a finding addressed to a stretch of **part two**, placed six to nine seconds
/// into that part — far enough from the part's own beginning that a head reading the clip's
/// position as a place on the rehearsal cannot be mistaken for a head on the stretch.
///
/// The team goes on telling past that stretch, so the ground it stopped on falls outside
/// the stretch's band: standing on the stretch the analyst points at, a head that never
/// moved would read the same as a head that jumped to it.
Future<ProviderContainer> _oAchadoNoTrechoDaParteDois(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await retroTocando(tester, harness, partes: 2);
  final notifier = container.read(salaSessionProvider.notifier);
  await _contarAte(tester, harness, notifier, _parteInteira);
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.proximaParte();
  await tester.pump(const Duration(milliseconds: 400));
  for (final ate in const [
    Duration(seconds: 3),
    _trechoDe,
    _trechoAte,
    Duration(seconds: 12),
  ]) {
    await _contarAte(tester, harness, notifier, ate);
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  final sala = container.read(salaSessionProvider);
  expect(sala.btFindingTrecho?.parte, 1,
      reason: 'o cenário só mede alguma coisa se o achado apontar a parte 2');
  expect(sala.btOuvidoMs, isNot(inInclusiveRange(_naCordaDe, _naCordaAte)),
      reason: 'e se o chão contado ficar fora da banda do trecho: em cima '
          'dela, uma cabeça que nunca se mexeu leria igual a uma que saltou');
  return container;
}

void main() {
  testWidgets('the bead walks the cord while the part plays', (tester) async {
    final harness = _umEnsaioQueCorre();
    final container = await retroTocando(tester, harness);

    final andados = <int>[];
    final lugares = <double>[];
    for (var vez = 0; vez < 4; vez++) {
      await tester.pump(const Duration(milliseconds: 400));
      andados.add(cabeca(tester));
      lugares.add(naCorda(tester));
    }

    for (var i = 1; i < andados.length; i++) {
      expect(andados[i], greaterThan(andados[i - 1]),
          reason: 'a cabeça de leitura só saltava no começo e no fim de cada parte; '
              'entre os saltos ficava parada enquanto o áudio corria');
    }
    expect(andados.last, lessThanOrEqualTo(_parteInteira.inMilliseconds),
        reason: 'a parte tem trinta segundos e a cabeça não pode passar do fim dela');
    expect(lugares.last, greaterThan(lugares.first),
        reason: 'não basta o número mudar: é o lugar na corda que a equipe olha');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('the bead stops where the audio stopped', (tester) async {
    final harness = _umEnsaioQueCorre();
    final container = await retroTocando(tester, harness);

    await tester.pump(const Duration(milliseconds: 400));
    container.read(salaSessionProvider.notifier).ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 100));
    final parou = cabeca(tester);
    expect(parou, greaterThan(0));

    // O player segue respondendo posições — a corda é que não pode mais ouvi-las.
    final antes = tester.widget<RetroCord>(find.byType(RetroCord));
    harness.playback.at = const Duration(seconds: 25);
    await tester.pump(const Duration(seconds: 2));

    expect(cabeca(tester), parou,
        reason: 'pausar é a sala guardando onde a equipe parou de ouvir; uma cabeça '
            'que anda depois disso desmente o que a pausa quer dizer');
    expect(identical(tester.widget<RetroCord>(find.byType(RetroCord)), antes), isTrue,
        reason: 'e a corda nem foi redesenhada: parar de ouvir é parar de perguntar. '
            'A equipe conta um trecho por minutos a fio com a gravação em pausa, e um '
            'timer que sobrevive a ela acorda o tablet dez vezes por segundo à toa');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('the bead does not walk with nothing playing', (tester) async {
    final harness = _umEnsaioQueCorre();
    await retroTocando(tester, harness);

    await tester.pump(const Duration(milliseconds: 400));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    final fim = cabeca(tester);

    harness.playback.at = const Duration(seconds: 12);
    await tester.pump(const Duration(seconds: 3));

    expect(cabeca(tester), fim,
        reason: 'sem áudio no ar não há andamento a acompanhar, e a bolinha fica onde '
            'a sala anotou que a equipe parou de ouvir');
  });

  testWidgets('the end of a part still leads on to the next', (tester) async {
    final harness = _umEnsaioQueCorre();
    final container = await retroTocando(tester, harness, partes: 2);

    await tester.pump(const Duration(milliseconds: 400));
    expect(cabeca(tester), lessThan(_parteInteira.inMilliseconds));

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    expect(cabeca(tester), _parteInteira.inMilliseconds,
        reason: 'o fim de uma parte é medido pela duração dela, não pela posição que o '
            'player responde no instante em que para');
    expect(
      tester.widget<RetroCord>(find.byType(RetroCord)).fimDasPartes,
      [_parteInteira.inMilliseconds, 2 * _parteInteira.inMilliseconds],
      reason: 'as duas partes foram medidas na entrada: a régua não espera que '
          'cada uma acabe de tocar para saber onde ela acaba',
    );

    container.read(salaSessionProvider.notifier).proximaParte();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cabeca(tester), greaterThan(_parteInteira.inMilliseconds),
        reason: 'atravessar a fronteira continua levando a equipe à parte seguinte, e a '
            'cabeça segue de lá para a frente');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('a part slow to open does not fling the bead to the end',
      (tester) async {
    final harness = _umEnsaioQueCorre();
    final container = await retroTocando(tester, harness, partes: 2);

    await tester.pump(const Duration(milliseconds: 400));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    // Um take longo num tablet velho leva mais que um tique da corda para abrir, e o
    // player responde pela parte anterior até abrir.
    harness.playback.holdNextOpening();
    container.read(salaSessionProvider.notifier).proximaParte();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cabeca(tester), _parteInteira.inMilliseconds,
        reason: 'a parte que abre ainda não soou; enquanto o player responde pela '
            'anterior, o único lugar que a sala sabe é o começo desta');

    harness.playback.finishHeldOpening();
    await tester.pump(const Duration(milliseconds: 16));

    expect(naCorda(tester), lessThan(0.75),
        reason: 'no quadro em que a parte abre, a sala aprende a duração dela — e uma '
            'cabeça herdada da parte anterior, medida contra essa duração, atirava a '
            'bolinha para a ponta do colar antes de voltar');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('the bead walks again when the take is let run on', (tester) async {
    final harness = _umEnsaioQueCorre();
    final container = await retroTocando(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await tester.pump(const Duration(milliseconds: 400));
    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 100));
    final parou = cabeca(tester);

    notifier.ouvirGravacao();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cabeca(tester), greaterThan(parou),
        reason: 'pausar para contar um trecho e deixar a gravação seguir é o gesto mais '
            'comum da retro; a cabeça tem de voltar a andar com ela');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('hearing the stretch the analyst pointed at walks the head along it',
      (tester) async {
    final harness = _umAchadoNaParteDois();
    final container = await _oAchadoNoTrechoDaParteDois(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    final contado = container.read(salaSessionProvider).btOuvidoMs;
    notifier.ouvirVozMaterna();
    await tester.pump(const Duration(milliseconds: 100));
    final primeiro = cabeca(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final depois = cabeca(tester);

    expect(primeiro, greaterThanOrEqualTo(_naCordaDe),
        reason: 'a cabeça salta para onde o trecho mora — o começo da parte 2 '
            'mais o lugar do trecho dentro dela — e não para a posição que o '
            'recorte responde, que é contada de dentro do próprio recorte');
    expect(depois, lessThanOrEqualTo(_naCordaAte),
        reason: 'e não passa do fim do lugar do trecho: a banda desenhada é o '
            'lugar, e a cabeça anda por cima dela');
    expect(depois, greaterThan(primeiro),
        reason: 'e anda: uma cabeça parada no começo do trecho não diz à '
            'equipe onde é que o som vai');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    expect(cabeca(tester), contado,
        reason: 'acabado o trecho, a cabeça volta ao chão contado, onde a '
            'tradução parou: ouvir um trecho não move o cursor de ninguém');
    expect(container.read(salaSessionProvider).btOuvidoMs, contado,
        reason: 'e o chão contado em si não se mexeu: ouvir um trecho é ouvir, '
            'não é contar, e o cursor de uma tradução retomada sai daqui');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('holding the stretch parks the head, and letting it run follows again',
      (tester) async {
    final harness = _umAchadoNaParteDois();
    final container = await _oAchadoNoTrechoDaParteDois(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final contado = container.read(salaSessionProvider).btOuvidoMs;

    notifier.ouvirVozMaterna();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cabeca(tester), greaterThan(_naCordaDe),
        reason: 'o cenário só mede alguma coisa com a cabeça já dentro da '
            'banda do trecho');

    notifier.ouvirVozMaterna();
    await tester.pump(const Duration(milliseconds: 200));

    expect(cabeca(tester), contado,
        reason: 'segurar o trecho é a equipe a parar de ouvir: a cabeça volta '
            'ao chão contado, e não fica pendurada onde o recorte estava');

    notifier.ouvirVozMaterna();
    await tester.pump(const Duration(milliseconds: 100));
    final voltou = cabeca(tester);
    await tester.pump(const Duration(milliseconds: 200));

    expect(voltou, greaterThanOrEqualTo(_naCordaDe),
        reason: 'a cabeça volta para dentro da banda, e não para o chão '
            'contado nem para o começo da parte');
    expect(cabeca(tester), lessThanOrEqualTo(_naCordaAte),
        reason: 'e continua sem passar do fim do lugar do trecho');
    expect(cabeca(tester), greaterThan(voltou),
        reason: 'e soltá-lo põe a cabeça a andar outra vez, de onde o recorte '
            'recomeça');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('hearing the telling in Portuguese leaves the head where it is',
      (tester) async {
    final harness = _umAchadoNaParteDois();
    final container = await _oAchadoNoTrechoDaParteDois(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    final parado = cabeca(tester);
    notifier.ouvirTraducaoEmPortugues();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cabeca(tester), parado,
        reason: 'a tradução em português é um arquivo à parte, que não mora em '
            'lugar nenhum do ensaio: a cabeça desenha onde a equipe ouviu a '
            'voz dela própria, e essa não se mexeu');
    await sairDaSala(tester, harness, container);
  });

  testWidgets('nothing keeps running once the screen is gone mid-stretch',
      (tester) async {
    final harness = _umAchadoNaParteDois();
    final container = await _oAchadoNoTrechoDaParteDois(tester, harness);

    container.read(salaSessionProvider.notifier).ouvirVozMaterna();
    await tester.pump(const Duration(milliseconds: 300));
    expect(cabeca(tester), greaterThan(_naCordaDe),
        reason: 'a tela tem de sair com a vigia do trecho mesmo a perguntar, '
            'ou o caso não olha para o relógio que interessa');

    await sairDaSala(tester, harness, container);
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(RetroCord), findsNothing,
        reason: 'e o flutter_test reprova um timer que sobreviveu à árvore '
            'descartada: a corda passou a perguntar também durante um trecho, '
            'e há um segundo caminho por onde o relógio pode ficar de pé');
  });

  testWidgets('nothing keeps running once the screen is gone', (tester) async {
    final harness = _umEnsaioQueCorre();
    final container = await retroTocando(tester, harness);

    await tester.pump(const Duration(milliseconds: 400));
    expect(cabeca(tester), greaterThan(0));

    await sairDaSala(tester, harness, container);
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(RetroCord), findsNothing,
        reason: 'e o flutter_test reprova um timer que sobreviveu à árvore descartada');
  });
}
