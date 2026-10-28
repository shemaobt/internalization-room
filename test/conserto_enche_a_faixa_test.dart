import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

SalaHarness? _harnessDaVez;

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

List<int> _apontados(ProviderContainer container) {
  final sessao = container.read(salaSessionProvider);
  return [
    for (final (lugar, trecho) in sessao.btTrechos.indexed)
      if (trecho.segmentId != null &&
          trecho.segmentId == sessao.btFindingSegmentId)
        lugar,
  ];
}

void _oConsertoEstaGravando(ProviderContainer container, {String? reason}) {
  expect(
    container.read(salaSessionProvider).btPhase,
    BtPhase.capturing,
    reason: reason,
  );
}

void _oTrechoEsperaOConserto(ProviderContainer container, {String? reason}) {
  final sessao = container.read(salaSessionProvider);
  expect(sessao.btPhase, isNot(BtPhase.capturing), reason: reason);
  expect(
    sessao.btTraducaoPendente,
    anyOf(isNull, sessao.btTraducaoEmprestada),
    reason: reason,
  );
  expect(_apontados(container), [0], reason: reason);
}

/// A session standing at the question, with a finding on the first of two stretches.
Future<ProviderContainer> _pumpToPergunta(
  WidgetTester tester, {
  Duration? teto,
  Duration? takeLandsInRealTime,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, busyCeiling: teto)
    ..room.verdictChecked = false
    ..room.verdictHasFinding = true
    ..room.verdictFindingSegmentId = 'trecho-1'
    ..room.takeLandsInRealTime = takeLandsInRealTime;
  _harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = _notifier(container);
  await sala.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    sala.retroTap();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<void> _escolherTraduzirDeNovo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  traduzirOApontadoDeNovo(container);
  await tester.pump(const Duration(milliseconds: 300));
}

/// The circle opens the microphone over the old telling.
Future<void> _abrirOMicrofone(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The microphone is open on the stretch; this is the team closing it and handing the
/// telling over with the check.
Future<void> _entregarATraducao(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'the retro opens on a part the room has named, not on one still in the air',
    (tester) async {
      final container = await _pumpToPergunta(
        tester,
        takeLandsInRealTime: const Duration(milliseconds: 300),
      );

      expect(
        container.read(salaSessionProvider).partes.single.takeId,
        'gravacao-1',
        reason:
            'a parte entrava no retro antes de a sala dar o nome, e o '
            'trecho contado de volta não tinha de quem ser',
      );
    },
  );

  testWidgets('o veredito aponta o trecho do achado, e só ele', (tester) async {
    final container = await _pumpToPergunta(tester);

    expect(
      _apontados(container),
      [0],
      reason:
          'o achado não apontava o trecho que o analista nomeou, ou '
          'apontava também o trecho que ninguém nomeou',
    );
  });

  testWidgets(
    'o conserto começa quando o círculo abre o microfone na língua-ponte',
    (tester) async {
      final container = await _pumpToPergunta(tester);
      final harness = _harnessDaVez!;
      final pedidos = harness.room.calls.length;

      await _escolherTraduzirDeNovo(tester, container);
      _oTrechoEsperaOConserto(
        container,
        reason:
            'escolher a voz já dava o conserto por começado, sem nada '
            'gravado ainda (quadro X2)',
      );

      await _abrirOMicrofone(tester, container);

      _oConsertoEstaGravando(
        container,
        reason:
            'abrir o microfone não começava o conserto antes de qualquer '
            'coisa ir para a sala',
      );
      expect(harness.room.calls.length, pedidos);
    },
  );

  testWidgets('uma gravação que não devolveu arquivo devolve o trecho à espera '
      'do conserto, sem chamar ninguém', (tester) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester, container);
    await _abrirOMicrofone(tester, container);
    _oConsertoEstaGravando(container);
    harness.recorder.returnsEmpty = true;
    await _entregarATraducao(tester, container);

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'uma gravação de tradução vazia não é um dos seis casos do sinal '
          'da pessoa',
    );
    _oTrechoEsperaOConserto(
      container,
      reason:
          'a gravação vazia seguia dada como conserto, e nada tinha sido '
          'consertado',
    );
    closeTheRoom(container);
  });

  testWidgets('um upload que a sala recusou deixa a tradução nova pendente', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester, container);
    await _abrirOMicrofone(tester, container);
    _oConsertoEstaGravando(container);
    harness.room.failReplaceWith = const Refused('UNAUTHORIZED');
    await _entregarATraducao(tester, container);

    final sessao = container.read(salaSessionProvider);
    expect(
      sessao.btTraducaoPendente,
      allOf(isNotNull, isNot(sessao.btTraducaoEmprestada)),
      reason:
          'a sala recusou o conserto e a tradução nova se perdia, em vez '
          'de seguir pendente até o check aterrar (ADR 0040)',
    );
    expect(_apontados(container), [0]);
    closeTheRoom(container);
  });

  testWidgets(
    'uma captura que a sala não aproveitou devolve o trecho à espera do conserto',
    (tester) async {
      final container = await _pumpToPergunta(tester);
      final harness = _harnessDaVez!;

      await _escolherTraduzirDeNovo(tester, container);
      await _abrirOMicrofone(tester, container);
      _oConsertoEstaGravando(container);
      harness.room.failReplaceWith = const Refused(RefusalCode.wordlessTelling);
      await _entregarATraducao(tester, container);

      _oTrechoEsperaOConserto(
        container,
        reason:
            'a sala não fez nada com o que subiu, e ficava uma tradução nova '
            'pendente sobre o trecho em vez de ele voltar a esperar o conserto',
      );
      expect(
        container.read(salaSessionProvider).canConfirmTranslation,
        isFalse,
        reason: 'só o círculo é oferecido, para contar o trecho de novo',
      );
    },
  );

  testWidgets(
    'uma parada que não devolveu arquivo devolve o trecho à espera do conserto',
    (tester) async {
      final container = await _pumpToPergunta(tester);
      final harness = _harnessDaVez!;

      await _escolherTraduzirDeNovo(tester, container);
      await _abrirOMicrofone(tester, container);
      _oConsertoEstaGravando(container);
      harness.recorder.returnsNothing = true;
      await _entregarATraducao(tester, container);

      expect(
        harness.room.replacesAsked,
        isEmpty,
        reason:
            'sem arquivo não há o que subir — se subir, este cenário deixou '
            'de medir uma falha',
      );
      _oTrechoEsperaOConserto(
        container,
        reason:
            'este ramo voltava calado, sem parar para uma pessoa e sem contar '
            'a falha, e o conserto ficava dado como começado sozinho',
      );
    },
  );

  testWidgets('um microfone que não abriu não dá o conserto por começado', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    harness.recorder.startThrows = true;
    await _escolherTraduzirDeNovo(tester, container);
    await _abrirOMicrofone(tester, container);
    await _abrirOMicrofone(tester, container);

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'na retro o microfone que não abre é calado: nem sinal, nem fala, '
          'nem contagem (ADR 0108)',
    );
    _oTrechoEsperaOConserto(
      container,
      reason:
          'a equipe se ofereceu para consertar e a sala não conseguiu '
          'ouvir: o conserto ficava dado como começado por um microfone que '
          'nunca abriu',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'voltar a gravar depois do microfone recusado começa o conserto',
    (tester) async {
      final container = await _pumpToPergunta(tester);
      final harness = _harnessDaVez!;

      harness.recorder.startThrows = true;
      await _escolherTraduzirDeNovo(tester, container);
      await _abrirOMicrofone(tester, container);
      _oTrechoEsperaOConserto(container);

      harness.recorder.startThrows = false;
      _notifier(container).teamTapped();
      await tester.pump(const Duration(milliseconds: 300));
      final capturasAntes = harness.recorder.captures;
      await _abrirOMicrofone(tester, container);

      expect(
        harness.recorder.captures,
        capturasAntes + 1,
        reason:
            'a pessoa veio e o toque volta a gravar — se não gravar, este '
            'cenário não chega ao que ele mede',
      );
      _oConsertoEstaGravando(
        container,
        reason:
            'o conserto retirado quando o microfone recusou não voltava a '
            'começar quando ele abriu, com a equipe gravando por cima',
      );
    },
  );

  testWidgets('a sala que desistiu de esperar devolve o trecho à espera do '
      'conserto, sem chamar ninguém', (tester) async {
    final container = await _pumpToPergunta(
      tester,
      teto: const Duration(seconds: 2),
    );
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester, container);
    await _abrirOMicrofone(tester, container);
    _oConsertoEstaGravando(container);
    // The one hang the ladder never sees: the room's own watchdog gives up on a busy
    // state, and it is not a room failure — it is this tablet deciding the wait is over.
    // Everything the mend awaits inside that window is local and has no timeout of its
    // own, and stopping the recorder is one of them.
    harness.recorder.holdNextStop();
    _notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'uma espera sem fala que se esgota solta o passo e não chama '
          'ninguém',
    );
    expect(
      harness.room.replacesAsked,
      isEmpty,
      reason: 'e a gravação nunca chegou a subir',
    );
    _oTrechoEsperaOConserto(
      container,
      reason:
          'era a falha sem nenhum outro sinal na tela: nada foi recusado, o '
          'círculo não estava offline, ninguém foi chamado, e o conserto '
          'seguia dado como em curso',
    );

    harness.recorder.finishStop();
    await tester.pump(const Duration(milliseconds: 200));
    closeTheRoom(container);
  });

  testWidgets('um veredito que reprova o mesmo trecho volta a apontá-lo', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    // The analyst is set to reprove the same place before the correction is handed over,
    // and by place rather than by name: mending retires the name it was pointing at and
    // mints a new one. Armed beforehand because the room asks for the result itself at the
    // end of a correction — naming the stretch afterwards would be answering a question
    // that had already been asked, and the second one the room rightly refuses.
    harness.room.verdictFindingPlace = 0;
    await _escolherTraduzirDeNovo(tester, container);
    await _abrirOMicrofone(tester, container);
    await _entregarATraducao(tester, container);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await _notifier(container).finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 400));

    _oTrechoEsperaOConserto(
      container,
      reason:
          'o conserto ficava dado como definitivo, e o analista que apontou '
          'o mesmo trecho outra vez não o punha de volta à espera',
    );
    expect(
      container.read(salaSessionProvider).btFindingSegmentId,
      container.read(salaSessionProvider).btTrechos.first.segmentId,
      reason:
          'e é o trecho vivo que está apontado, não um nome que o '
          'servidor aposentou — um ponteiro defasado esvaziaria faixa nenhuma '
          'e este cenário passaria sem medir nada',
    );
  });

  testWidgets('consertar não mexe no pedaço de cordão do vizinho', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final vizinhoAntes = container
        .read(salaSessionProvider)
        .btTrechos
        .firstWhere((trecho) => trecho.segmentId == 'trecho-2');

    await _escolherTraduzirDeNovo(tester, container);
    await _abrirOMicrofone(tester, container);
    await _entregarATraducao(tester, container);

    // Where the bands sit, which the drained-places reading cannot see: it answers which
    // stretch is waiting, not how much cord each one covers. A mend that moved its
    // neighbour would slide that band along the cord in full view of a team that has no
    // other way to read progress.
    final trechos = container.read(salaSessionProvider).btTrechos;
    expect(
      trechos,
      hasLength(2),
      reason:
          'consertar preenche o trecho que estava esperando; não '
          'acrescenta um terceiro ao lado dele',
    );
    expect(trechos[1].segmentId, vizinhoAntes.segmentId);
    expect(trechos[1].from, vizinhoAntes.from);
    expect(
      trechos[1].to,
      vizinhoAntes.to,
      reason:
          'e o pedaço de cordão que ela ocupa é o mesmo — correção é '
          'localizada, que é a promessa do modelo inteiro',
    );
  });
}
