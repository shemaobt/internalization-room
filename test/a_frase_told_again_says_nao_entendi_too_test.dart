import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        confirmar,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tesoura,
        tocar;

const _naoEntendi = 'não entendi — traduzam de novo esse pedaço';
const _deNovo = 'Tocar para gravar a tradução de novo';

String _barra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 3200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _vereditoNaFraseUm(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocar(tester, tesoura);
  await gravarATraducao(tester);
  await tocar(tester, confirmar);
  await contarAteOFimDaParte(tester, harness);
  await waitFor(
    'as duas frases ficarem contadas',
    () =>
        container
            .read(salaSessionProvider)
            .btTrechos
            .where((trecho) => trecho.contado)
            .length ==
        2,
    step: () => _passo(tester),
  );
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 0
    ..verdictFindings = const [
      BtFinding(kind: BtFindingKind.addition, frase: 1, segmentId: 'trecho-1'),
    ];
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<void> _deNovoNoCirculo(WidgetTester tester) async {
  await tester.tap(find.byType(FacilitatorCircle));
  await _passo(tester);
  await tester.tap(find.byType(FacilitatorCircle));
  await _passo(tester);
}

Future<void> _caiNaRede(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tocar(tester, confirmar);
  await waitFor('a frase voltar da rede', () {
    final estado = container.read(salaSessionProvider);
    return estado.wordlessTelling || estado.unreachable;
  }, step: () => _passo(tester));
}

void main() {
  testWidgets('a frase told again whose send fails on the network says «não '
      'entendi», keeps its stretch, and is never sent again on its own', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final gravacao = harness.room.takeIds.first;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);

    harness.room.failReplaceWith = const NetworkFailed('sem rede');
    await _caiNaRede(tester, container);
    harness.room.failReplaceWith = null;
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    final estado = container.read(salaSessionProvider);
    expect(
      find.text(_naoEntendi),
      findsOneWidget,
      reason:
          'a frase traduzida de novo que a rede perdia virava sem conexão, '
          'sem a fala dela',
    );
    expect(estado.offline, isFalse);
    expect(estado.unreachable, isFalse);
    expect(
      harness.room.replaceKeys,
      hasLength(1),
      reason:
          'a frase traduzida de novo era reenviada sozinha quando a rede '
          'voltava',
    );

    await _deNovoNoCirculo(tester);
    await tocar(tester, confirmar);
    expect(
      harness.room.replacesAsked,
      ['trecho-1@$gravacao:0-4000'],
      reason:
          'a frase é traduzida de novo no mesmo pedaço, de onde a outra era',
    );
    closeTheRoom(container);
  });

  testWidgets('three frases told again in a row whose send fails on the '
      'network call no person and never show the room as gone', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    harness.room.failReplaceWith = const NetworkFailed('sem rede');

    for (var vez = 1; vez <= 3; vez++) {
      if (vez > 1) await _deNovoNoCirculo(tester);
      await tocar(tester, confirmar);
      await waitFor('a frase $vez voltar da rede', () {
        final estado = container.read(salaSessionProvider);
        return harness.room.replaceKeys.length >= vez &&
            (estado.wordlessTelling || estado.unreachable);
      }, step: () => _passo(tester));
    }
    await _passo(tester);

    final estado = container.read(salaSessionProvider);
    expect(
      estado.offline,
      isFalse,
      reason:
          'cada frase traduzida de novo que a rede perdia punha a sala em '
          'sem conexão',
    );
    expect(estado.needsPerson, isFalse);
    expect(harness.room.replaceKeys, hasLength(3));
    closeTheRoom(container);
  });

  testWidgets('a frase told again whose answer was lost, told once more, '
      'lands as that one frase, the team\'s latest telling', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final gravacao = harness.room.takeIds.first;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);

    harness.room.loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _caiNaRede(tester, container);
    expect(find.text(_naoEntendi), findsOneWidget);

    await _deNovoNoCirculo(tester);
    final segunda = container.read(salaSessionProvider).btTraducaoPendente!;
    await tocar(tester, confirmar);
    await waitFor(
      'a segunda pousar',
      () => container.read(salaSessionProvider).btTraducaoPendente == null,
      step: () => _passo(tester),
    );

    expect(
      harness.room.replacesAsked,
      ['trecho-1@$gravacao:0-4000', 'trecho-1-v1@$gravacao:0-4000'],
      reason:
          'a frase guardada com a resposta perdida e a contada de novo '
          'viravam duas, ou a de novo esperava um ✓ que nada pedia',
    );
    expect(harness.room.replacesComArquivo.last, segunda);
    final estado = container.read(salaSessionProvider);
    expect(
      [for (final trecho in estado.btTrechos) trecho.segmentId],
      [for (final segmento in harness.room.segments) segmento.segmentId],
      reason: 'uma frase no pedaço, a que o servidor tem',
    );
    expect(estado.needsPerson, isFalse);
    expect(estado.offline, isFalse);
    closeTheRoom(container);
  });

  testWidgets('a telling refused because its frase was told again meanwhile '
      'goes on to the frase standing on that slice, not back to the team', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final gravacao = harness.room.takeIds.first;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    final contada = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room.loseTheNextReplaceAnswerAndLandItLaterWith = const Refused(
      'BAD_REQUEST',
    );
    await tocar(tester, confirmar);
    harness.room.landTheLostReplace();
    await tocar(tester, confirmar);
    await waitFor(
      'a frase pousar',
      () => container.read(salaSessionProvider).btTraducaoPendente == null,
      step: () => _passo(tester),
    );

    expect(
      harness.room.replacesAsked,
      ['trecho-1@$gravacao:0-4000', 'trecho-1-v1@$gravacao:0-4000'],
      reason:
          'a recusa armava a frase que está no pedaço agora e esperava '
          'outro ✓ que nada na tela pedia',
    );
    expect(harness.room.replacesComArquivo.last, contada);
    expect(
      container.read(salaSessionProvider).btTrechos.first.segmentId,
      harness.room.segments.first.segmentId,
    );
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    closeTheRoom(container);
  });

  testWidgets('the read after a refused telling that falls on the network is '
      'a frase not understood too, and nothing goes again on its own', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    harness.room.loseTheNextReplaceAnswerAndLandItLaterWith = const Refused(
      'BAD_REQUEST',
    );
    await tocar(tester, confirmar);
    harness.room.landTheLostReplace();
    final pedidos = harness.room.replaceKeys.length;

    harness.room.failStateOnceWith = const NetworkFailed('sem rede');
    await tocar(tester, confirmar);
    await waitFor('a leitura voltar da rede', () {
      final estado = container.read(salaSessionProvider);
      return estado.wordlessTelling ||
          estado.unreachable ||
          harness.room.replaceKeys.length > pedidos + 1;
    }, step: () => _passo(tester));
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    final estado = container.read(salaSessionProvider);
    expect(
      find.text(_naoEntendi),
      findsOneWidget,
      reason: 'a leitura que caía punha a sala em sem conexão, sem a fala dela',
    );
    expect(estado.offline, isFalse);
    expect(estado.unreachable, isFalse);
    expect(
      harness.room.replaceKeys,
      hasLength(pedidos + 1),
      reason: 'a frase recusada era mandada de novo quando a rede voltava',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase told again whose key is still in flight after three '
      'answers goes out of reach and goes again under that key, as before', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final gravacao = harness.room.takeIds.first;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    final pedidos = harness.room.replaceKeys.length;

    harness.network.reachable = false;
    harness.room.replaceAnswersFirst.addAll(
      List.filled(3, const Refused(RefusalCode.idempotencyKeyInFlight)),
    );
    await _caiNaRede(tester, container);
    expect(
      container.read(salaSessionProvider).unreachable,
      isTrue,
      reason: 'a chave ainda em voo não é uma frase perdida: o servidor a tem',
    );
    expect(find.text(_naoEntendi), findsNothing);

    harness.network
      ..reachable = true
      ..networkComesBack();
    await waitFor(
      'a frase pousar sob a mesma chave',
      () => container.read(salaSessionProvider).btTraducaoPendente == null,
      step: () => _passo(tester),
    );
    expect(harness.room.replaceKeys.skip(pedidos), hasLength(4));
    expect(harness.room.replaceKeys.skip(pedidos).toSet(), hasLength(1));
    expect(harness.room.replacesAsked, ['trecho-1@$gravacao:0-4000']);
    closeTheRoom(container);
  });

  testWidgets('the copy kept of a frase told again whose answer was lost '
      'leaves the queue once the next telling finds that it landed', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final fila = harness.takes as FakeTakeQueue;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    final perdida = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room
      ..refuseTake = 'retro/${KeptScope.whole}'
      ..loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _caiNaRede(tester, container);
    await waitFor(
      'a cópia da perdida entrar na fila',
      () => fila.rows.any((linha) => linha.path == perdida),
      step: () => letTheRehearsalReachTheRoom(tester),
    );

    await _deNovoNoCirculo(tester);
    await tocar(tester, confirmar);
    await waitFor(
      'a segunda pousar',
      () => container.read(salaSessionProvider).btTraducaoPendente == null,
      step: () => _passo(tester),
    );
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    expect(
      fila.rows.where((linha) => linha.path == perdida),
      isEmpty,
      reason:
          'a perdida já é a frase no servidor; na fila ela subiria de novo '
          'como uma tomada da passagem inteira',
    );
    closeTheRoom(container);
  });

  testWidgets('the copy kept of a frase told again whose answer was lost '
      'leaves the queue too when the next telling finds the frase gone', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final fila = harness.takes as FakeTakeQueue;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    final perdida = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room
      ..refuseTake = 'retro/${KeptScope.whole}'
      ..loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _caiNaRede(tester, container);
    await waitFor(
      'a cópia da perdida entrar na fila',
      () => fila.rows.any((linha) => linha.path == perdida),
      step: () => letTheRehearsalReachTheRoom(tester),
    );

    harness.room.recordThePartAgain(harness.room.takeIds.first);
    await _deNovoNoCirculo(tester);
    await tocar(tester, confirmar);
    await waitFor(
      'a frase sumir da fileira',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    expect(
      fila.rows.where((linha) => linha.path == perdida),
      isEmpty,
      reason:
          'a perdida ficava na fila e subia como uma tomada da passagem '
          'inteira de uma parte que a equipe gravou de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('the copy kept of a frase told again whose answer was lost '
      'leaves the queue when the team leaves the passage', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseUm(tester, harness);
    final fila = harness.takes as FakeTakeQueue;
    await tocar(tester, _barra(1));
    await gravarATraducao(tester, circulo: _deNovo);
    final perdida = container.read(salaSessionProvider).btTraducaoPendente!;

    harness.room
      ..refuseTake = 'retro/${KeptScope.whole}'
      ..loseTheNextReplaceAnswerWith = const NetworkFailed('timeout');
    await _caiNaRede(tester, container);
    await waitFor(
      'a cópia da perdida entrar na fila',
      () => fila.rows.any((linha) => linha.path == perdida),
      step: () => letTheRehearsalReachTheRoom(tester),
    );

    container.read(salaSessionProvider.notifier).leaveThePassage();
    for (var passo = 0; passo < 5; passo++) {
      await letTheRehearsalReachTheRoom(tester);
    }

    expect(
      fila.rows.where((linha) => linha.path == perdida),
      isEmpty,
      reason:
          'a perdida ficava na fila depois da passagem e subia como uma '
          'tomada da passagem inteira de uma frase que talvez já esteja lá',
    );
    closeTheRoom(container);
  });
}
