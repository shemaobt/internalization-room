import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const _micMaterna =
    'Gravar esta parte de novo na língua materna';
const _micRetro = 'Traduzir de novo só em português';

Finder _byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

SalaHarness? _harnessDaVez;

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// The lines the room has for "could you say that again?" — the ones an inaudible turn in
/// the conversation gets. A mend that did not take is told with one of these, and nothing
/// new.
final Set<String> _falasDeRepetir = {
  for (final line in inaudibleLines) fixedLineAsset(line, testLanguage),
};

String get _falaDePessoa => fixedLineAsset(needsPersonLine, testLanguage);

int _vezesQuePediuParaRepetir(SalaHarness harness) =>
    harness.voice.assets.where(_falasDeRepetir.contains).length;

/// Which places on the cord are drawn drained, by their order along it.
List<int> _faixasVazias(WidgetTester tester, ProviderContainer container) {
  final cord = tester.widget<RetroCord>(find.byType(RetroCord));
  final trechos = container.read(salaSessionProvider).btTrechos;
  return [
    for (var lugar = 0; lugar < trechos.length; lugar++)
      if (cord.apontado != null && trechos[lugar].segmentId == cord.apontado)
        lugar,
  ];
}

/// A session standing at the question, with a finding on the first of two stretches.
///
/// Any finding but a missing one: what these cases drive is the long way's first station,
/// chosen from the question that offers both voices, and a missing stretch is not offered
/// that question — it gets a single exit of its own.
Future<ProviderContainer> _pumpToPergunta(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingSegmentId = 'trecho-1';
  _harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = _notifier(container);
  await sala.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    sala.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  harness.voice.assets.clear();
  return container;
}

/// The long way's first gesture: choosing to re-record the mother tongue.
Future<void> _escolherRegravarAMaterna(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(salaSessionProvider.notifier).regravarAVozMaterna();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Tap to start, tap to stop: the mother tongue recorded again.
Future<void> _gravarAMaterna(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  _notifier(container).retroTap();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

/// The whole long way's first station, with the room set to fail it somewhere.
Future<void> _regravarAMaternaQueNaoPega(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _escolherRegravarAMaterna(tester, container);
  await _gravarAMaterna(tester, container);
}

void main() {
  testWidgets('a materna que não pega devolve a equipe à pergunta',
      (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    harness.playback.measured = null;

    await _regravarAMaternaQueNaoPega(tester, container);

    final estado = container.read(salaSessionProvider);
    expect(harness.room.replacesAsked, isEmpty,
        reason: 'um áudio sem medida não chega a substituir nada — se chegar, '
            'este cenário deixou de medir uma falha');
    expect(estado.btPhase, BtPhase.findings,
        reason: 'a equipe volta à pergunta de onde saiu, não à reprodução, '
            'onde tocar não faz nada');
    expect(_byLabel(_micMaterna), findsOneWidget,
        reason: 'e as saídas de correção estão na tela: é assim que se tenta '
            'de novo');
    expect(_byLabel(_micRetro), findsOneWidget);
    expect(estado.needsPerson, isFalse,
        reason: 'uma falha só não é motivo para chamar alguém');
  });

  testWidgets('a sala diz que não pegou, na primeira falha', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    harness.playback.measured = null;

    await _regravarAMaternaQueNaoPega(tester, container);

    expect(harness.voice.assets, hasLength(1),
        reason: 'a linha fixa de repetir é dita uma vez, na primeira falha — '
            'não na terceira — e nada mais: nem a de chamar alguém, nem '
            'fala nova');
    expect(_falasDeRepetir, contains(harness.voice.assets.single),
        reason: 'e é uma das que a captura vazia já usa');
  });

  testWidgets('um áudio de duração zero é a mesma porta', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    harness.playback.measured = Duration.zero;

    await _regravarAMaternaQueNaoPega(tester, container);

    expect(harness.room.replacesAsked, isEmpty);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(harness.voice.assets, hasLength(1));
    expect(_falasDeRepetir, contains(harness.voice.assets.single));
  });

  testWidgets('um take que a sala não nomeou é a mesma porta', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    (harness.takes as FakeTakeQueue).forgetsNames = true;

    await _regravarAMaternaQueNaoPega(tester, container);

    expect(harness.room.replacesAsked, isEmpty,
        reason: 'sem nome não há o que mandar substituir');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(harness.voice.assets, hasLength(1));
    expect(_falasDeRepetir, contains(harness.voice.assets.single));
  });

  testWidgets('a linha de repetir não entra na gravação nova', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    harness.playback.measured = null;
    await _regravarAMaternaQueNaoPega(tester, container);
    final antes = harness.voice.stops;

    // The team is quick: they choose the wood voice and tap to record while the room may
    // still be asking them to say it again.
    await _escolherRegravarAMaterna(tester, container);
    _notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.voice.stops, greaterThan(antes),
        reason: 'abrir o microfone cala a sala — senão a pergunta do tablet '
            'entra na voz materna nova, como um trecho gravado por cima');
  });

  testWidgets('a faixa continua vazia', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherRegravarAMaterna(tester, container);
    expect(_faixasVazias(tester, container), isEmpty);
    harness.playback.measured = null;
    await _gravarAMaterna(tester, container);

    expect(_faixasVazias(tester, container), [0],
        reason: 'a promessa foi retirada e continua retirada: dizer que não '
            'pegou não muda o fato de que nada foi consertado');
  });

  testWidgets('a substituição que levanta chega ao mesmo lugar',
      (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherRegravarAMaterna(tester, container);
    harness.room.failReplaceWith = const RoomBroke('a sala caiu no meio');
    await _gravarAMaterna(tester, container);

    final estado = container.read(salaSessionProvider);
    expect(harness.room.calls, contains('replaceSegment'),
        reason: 'esta é a segunda porta: a sala foi chamada e levantou');
    expect(estado.btPhase, BtPhase.findings);
    expect(_byLabel(_micMaterna), findsOneWidget);
    expect(_byLabel(_micRetro), findsOneWidget);
    expect(estado.needsPerson, isFalse);
    expect(_vezesQuePediuParaRepetir(harness), 1);
    expect(_faixasVazias(tester, container), [0]);
  });

  testWidgets('tentar de novo funciona', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherRegravarAMaterna(tester, container);
    harness.room.failReplaceWith = const RoomBroke('a sala caiu no meio');
    await _gravarAMaterna(tester, container);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);

    harness.room.failReplaceWith = null;
    await _escolherRegravarAMaterna(tester, container);
    await _gravarAMaterna(tester, container);

    final estado = container.read(salaSessionProvider);
    expect(estado.btPhase, BtPhase.capturing,
        reason: 'a gravação pegou e a segunda estação abriu sozinha, como no '
            'caminho longo normal');
    expect(harness.room.replacesSemArquivo, ['trecho-1'],
        reason: 'a voz nova subiu uma vez, para o trecho apontado — a volta '
            'não deixou estado sujo que mandasse a segunda para outro lugar');
    expect(estado.btFindingTrecho!.segmentId, isNot('trecho-1'),
        reason: 'e o ponteiro seguiu para a versão nova');
    expect(estado.btFindingTrecho!.takeId, harness.room.takeIds.last);
    expect(_faixasVazias(tester, container), isEmpty,
        reason: 'a faixa enche de novo sobre um conserto que agora está de pé');
    expect(_vezesQuePediuParaRepetir(harness), 1,
        reason: 'a linha foi dita na falha e só nela — a gravação que pegou '
            'não pede nada');
  });

  testWidgets(
      'uma recusa na substituição chama uma pessoa; o toque longo só '
      'pergunta, e é a mesa quem resolve', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherRegravarAMaterna(tester, container);
    harness.room.failReplaceWith = const RoomRefused();
    await _gravarAMaterna(tester, container);

    final estado = container.read(salaSessionProvider);
    expect(estado.btPhase, BtPhase.findings,
        reason: 'a pergunta fica na tela para quando a pessoa resolver');
    expect(estado.needsPerson, isTrue,
        reason: 'uma recusa continua sendo caso de pessoa, como sempre foi');
    expect(harness.voice.assets, [_falaDePessoa],
        reason: 'a sala já falou ao chamar alguém; não fala por cima');

    // O toque longo, com a sessão viva e a parada confirmada pelo servidor,
    // só pede uma releitura na hora — não derruba o aviso por si.
    _notifier(container).resolveWithPerson();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason: 'o servidor ainda segura a parada; soltar no toque poria a '
          'equipe de volta a falar dentro de uma sala que a mesa não '
          'atendeu',
    );
    expect(harness.voice.assets, [_falaDePessoa],
        reason: 'sem pedir para repetir: a mesma linha de chamar alguém, e '
            'nenhuma outra por cima');

    // Quando o servidor deixa de dizer needs_person — a mesa atendeu —, a
    // sala volta sozinha ao convite, sem precisar de um novo toque.
    harness.room.theDeskAttended();
    await tester.pump(const Duration(milliseconds: 300));

    final depois = container.read(salaSessionProvider);
    expect(depois.btPhase, BtPhase.findings);
    expect(depois.voice, VoiceState.invite,
        reason: 'a vigia lê o estado sozinha; quem levanta a parada é a '
            'mesa, não o toque');
    expect(_byLabel(_micMaterna), findsOneWidget);
    expect(_byLabel(_micRetro), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a rede que cai na substituição não pede para repetir',
      (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherRegravarAMaterna(tester, container);
    harness.room.failReplaceWith = const RoomUnavailable('sem rede');
    await _gravarAMaterna(tester, container);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings,
        reason: 'a pergunta fica na tela para quando a rede voltar');
    expect(harness.voice.assets, contains(offlineNoticeAsset(testLanguage)),
        reason: 'a sala avisa que ficou sem conexão, como sempre avisou');
    expect(_vezesQuePediuParaRepetir(harness), 0,
        reason: 'e não pede para repetir por cima do aviso');
  });

  testWidgets('a terceira falha seguida ainda chama uma pessoa, sem falar por cima',
      (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    harness.room.failReplaceWith = const RoomBroke('a sala caiu no meio');

    for (var vez = 0; vez < 3; vez++) {
      await _regravarAMaternaQueNaoPega(tester, container);
    }

    final estado = container.read(salaSessionProvider);
    expect(estado.needsPerson, isTrue,
        reason: 'a escada de três falhas continua de pé por baixo');
    expect(estado.btPhase, BtPhase.findings,
        reason: 'e a pergunta continua na tela para quando a pessoa resolver');
    expect(_vezesQuePediuParaRepetir(harness), 2,
        reason: 'nas duas primeiras a sala pede para repetir; na terceira ela '
            'chama alguém, e não diz as duas coisas ao mesmo tempo');
    expect(harness.voice.assets.where((a) => a == _falaDePessoa), hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('a captura vazia continua como estava', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    harness.recorder.returnsEmpty = true;

    await _regravarAMaternaQueNaoPega(tester, container);

    final estado = container.read(salaSessionProvider);
    expect(harness.room.replacesAsked, isEmpty);
    expect(estado.btPhase, BtPhase.findings,
        reason: 'a captura vazia é o modelo: já voltava à pergunta');
    expect(estado.needsPerson, isTrue,
        reason: 'e já parava para uma pessoa — isso não pode ter mudado');
    expect(harness.voice.assets, [_falaDePessoa],
        reason: 'ela diz só a linha de chamar alguém; a linha de repetir '
            'pertence à falha da sala, não ao arquivo sem byte');
    closeTheRoom(container);
  });
}
