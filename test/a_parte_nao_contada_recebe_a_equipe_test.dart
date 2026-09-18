import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// A team standing on part 2 recorded again, over a rehearsal told back whole, reached the
/// way ADR 0020 has it: through a finding, the long way, and back to the retro. Part 2 is
/// in the air from its own beginning and nothing has told it back yet.
Future<Sala> _parteDoisRegravadaENuncaContada() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.missing
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  expect(it.estado.btFindingTrecho?.parte, 1,
      reason: 'o cenário só mede alguma coisa se o achado apontar a parte 2');

  it.sala.gravarAParteDeNovo();
  await regravarAParte(it, 1);
  await waitFor(
    'a sala nomear a parte gravada de novo',
    () => it.partes[1].takeId != null,
  );
  it.harness.playback.lengths[it.partes[1].path] = partesDoEnsaio[1];

  it.harness.room
    ..verdictFinding = null
    ..verdictFindingPlace = null;
  it.sala.startRetro();
  await waitFor(
    'a tradução recomeçar na parte gravada de novo',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  return it;
}

/// The same team, having let part 2 play to its end without telling anything and crossed
/// on to part 3 (already told, in an earlier round) so *terminei* is lit again: this ticket
/// answers the second errand, not the first, so the button that asks for the check has to
/// be lit the ordinary way before a test can press it.
Future<Sala> _prontaParaTerminarComParteNaoContada() async {
  final it = await _parteDoisRegravadaENuncaContada();
  it.harness.playback.length = partesDoEnsaio[1];
  it.harness.playback.at = partesDoEnsaio[1];
  it.harness.playback.finishPlayback();
  await waitFor(
    'a segunda parte acabar e abrir a travessia',
    () => it.estado.btParteFronteira,
  );

  it.sala.ouvirGravacao();
  await waitFor(
    'a terceira parte entrar no ar',
    () => !it.estado.btParteFronteira && it.harness.playback.sounding,
  );
  it.harness.playback.length = partesDoEnsaio[2];
  it.harness.playback.at = partesDoEnsaio[2];
  it.harness.playback.finishPlayback();
  await waitFor(
    'o terminei acender',
    () => it.estado.canFinishBackTranslation,
  );
  return it;
}

void main() {
  test('um servidor que nomeia uma parte não contada não recusa nada por si',
      () {
    final ausente = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'findings_remaining': 0,
    });
    expect(ausente.untoldTakeIds, isEmpty);

    final nulo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'untold_take_ids': null,
      'findings_remaining': 0,
    });
    expect(nulo.untoldTakeIds, isEmpty,
        reason: 'uma recusa só existe quando o servidor a nomeia; lê-la de '
            'uma ausência é a inferência que a sala não faz');

    final nomeadas = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'untold_take_ids': ['t2'],
      'findings_remaining': 0,
    });
    expect(nomeadas.untoldTakeIds, ['t2']);

    final recusa = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/parte-nao-contada',
      'checked': false,
      'untold_take_ids': ['t2'],
      'findings_remaining': 0,
    });
    expect(recusa.untoldSegmentId, isNull);
    expect(recusa.unheardTakeIds, isEmpty);
  });

  test('a recusa por parte não contada pousa a equipe nela do começo',
      () async {
    final it = await _prontaParaTerminarComParteNaoContada();
    final segunda = it.partes[1];

    it.harness.room
      ..verdictChecked = false
      ..verdictUntoldTakeIds = [segunda.takeId!];
    final falasAntes = it.harness.voice.played.length;

    await pedirOVeredito(it);

    expect(it.harness.voice.played.skip(falasAntes),
        contains(falaDaParteNaoContada),
        reason: 'a sala diz a linha que o servidor compôs para esta recusa, '
            'e não a de um veredito qualquer');
    expect(it.estado.btPhase, BtPhase.playing,
        reason: 'sair do pensando é o que devolve o toque à equipe');
    expect(it.estado.btFindings, isEmpty,
        reason: 'uma parte não contada não é um achado do analista');
    expect(it.harness.playback.played.last, segunda.path,
        reason: 'a equipe cai na parte que o servidor nomeou');
    expect(it.harness.playback.playedFrom.last, Duration.zero,
        reason: 'a parte não contada não tem chão traduzido: o pouso começa '
            'do zero dela');
    expect(it.estado.btClipRodando, isTrue,
        reason: 'a parte entra no ar sozinha, sem mais um toque');
    expect(it.estado.btConsertando, isFalse);
    expect(it.estado.canFinishBackTranslation, isFalse,
        reason: 'a parte acabou de entrar no ar e ninguém a ouviu ainda');
  });

  test('terminei abre de novo assim que a parte não contada toca inteira',
      () async {
    final it = await _prontaParaTerminarComParteNaoContada();
    final segunda = it.partes[1];

    it.harness.room
      ..verdictChecked = false
      ..verdictUntoldTakeIds = [segunda.takeId!];
    await pedirOVeredito(it);

    expect(it.estado.canFinishBackTranslation, isFalse,
        reason: 'a parte acabou de pousar de novo: ninguém a ouviu ainda '
            'nesta rodada');

    it.harness.playback.at = partesDoEnsaio[1];
    it.harness.playback.finishPlayback();
    await waitFor('a segunda parte acabar (2ª vez)', () => it.estado.btClipEnded);

    expect(it.estado.canFinishBackTranslation, isTrue,
        reason: 'ouvida a parte não contada, o terminei acende de novo');
  });

  test('o primeiro corte depois do pouso conta do começo da parte',
      () async {
    final it = await _prontaParaTerminarComParteNaoContada();
    final segunda = it.partes[1];

    it.harness.room
      ..verdictChecked = false
      ..verdictUntoldTakeIds = [segunda.takeId!];
    await pedirOVeredito(it);

    final trechosAntes = it.estado.btTrechos.length;
    it.harness.playback.at = const Duration(seconds: 4);
    it.sala.cortarTrecho();
    await waitFor(
      'o microfone abrir',
      () => it.estado.btPhase == BtPhase.capturing,
    );
    it.sala.retroTap();
    await waitFor(
      'o trecho traduzido entrar no colar',
      () => it.estado.btTrechos.length > trechosAntes,
    );

    final trecho = it.estado.btTrechos.last;
    expect(trecho.parte, 1);
    expect(trecho.from, Duration.zero);
    expect(trecho.to, const Duration(seconds: 4));
  });

  test('um id que nenhuma parte tem chama uma pessoa', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final tocadas = it.harness.playback.played.length;
    final medidasAntes = it.harness.playback.measurements.length;

    it.harness.room
      ..verdictChecked = false
      ..verdictUntoldTakeIds = ['ninguem'];
    await pedirOVeredito(it);

    expect(it.estado.needsPerson, isTrue,
        reason: 'um nome que este tablet não sabe virar parte nenhuma é uma '
            'pessoa, e não uma tela a mais para a equipe adivinhar');
    expect(it.estado.btPhase, isNot(BtPhase.thinking));
    expect(it.harness.playback.played.length, tocadas,
        reason: 'não há parte em que cair, então nada entra no ar');
    expect(it.harness.playback.measurements.length, medidasAntes,
        reason: 'a parada chega antes de qualquer medida');
  });

  test('nomeadas várias, a equipe cai na primeira', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final primeira = it.partes[0];
    final terceira = it.partes[2];
    it.harness.room
      ..verdictChecked = false
      ..verdictUntoldTakeIds = [primeira.takeId!, terceira.takeId!];
    await pedirOVeredito(it);

    expect(it.harness.playback.played.last, primeira.path);
  });

  test('uma recusa atrasada não muda nada', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro(
      tetoDaEspera: const Duration(seconds: 2),
    );
    final terceira = it.partes[2];
    final tocadas = it.harness.playback.played.length;

    it.harness.room
      ..verdictChecked = false
      ..verdictUntoldTakeIds = [terceira.takeId!];
    it.harness.voice.holdNextFetch();

    final aperto = it.sala.finishBackTranslation();
    await waitFor(
      'a sala desistir da espera e chamar uma pessoa',
      () => it.estado.needsPerson,
    );
    it.harness.voice.finishHeldFetch();
    await aperto;

    expect(it.harness.playback.played.length, tocadas,
        reason: 'a sala já desistiu desta espera e parou para uma pessoa');
    expect(it.estado.needsPerson, isTrue);
  });
}
