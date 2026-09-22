import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const _micRetro = 'Traduzir de novo só em português';

Finder _byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

SalaHarness? _harnessDaVez;

SalaSessionNotifier _notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// Which places on the cord are drawn drained, by their order along it.
///
/// This reads the painter's own rule from outside: a band is emptied — and wears the halo
/// — exactly when the stretch it draws is the one the cord was told to point at. Stretches
/// are named by their place and not by their name, because mending mints a new name and
/// the band the team watches is the same band either way.
///
/// The whole list rather than one place at a time. Asking "is the neighbour's band full?"
/// reads like coverage and is not: the cord is told to point at one name, the neighbour
/// never carries that name, and the answer is false however broken the room is. Answering
/// with every drained place says the same thing and can be wrong.
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
Future<ProviderContainer> _pumpToPergunta(
  WidgetTester tester, {
  Duration? teto,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, busyCeiling: teto)
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
  return container;
}

/// The short way, which opens the microphone on the stretch straight away.
Future<void> _escolherTraduzirDeNovo(WidgetTester tester) async {
  await tester.tap(_byLabel(_micRetro));
  await tester.pump(const Duration(milliseconds: 300));
}

/// The microphone is open on the stretch; this is the team handing the telling over.
Future<void> _entregarATraducao(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).retroTap();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('o veredito esvazia a faixa apontada, e só a dela', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);

    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'a faixa vazia é a única coisa nesta sala que diz *onde* está o '
          'problema, para uma equipe que não lê — e o trecho que ninguém '
          'apontou continua em ordem',
    );
  });

  testWidgets('a faixa enche ao escolher traduzir de novo só na língua-ponte', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;
    final pedidos = harness.room.calls.length;

    await _escolherTraduzirDeNovo(tester);

    expect(
      _faixasVazias(tester, container),
      isEmpty,
      reason:
          'a promessa é feita ao escolher, antes de qualquer coisa ir '
          'para a sala: a faixa está de pé porque o conserto começou',
    );
    expect(harness.room.calls.length, pedidos);
  });

  testWidgets('uma gravação que não devolveu arquivo esvazia a faixa de novo', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester);
    expect(_faixasVazias(tester, container), isEmpty);
    harness.recorder.returnsEmpty = true;
    await _entregarATraducao(tester, container);

    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason:
          'gravação sem um byte dentro é o caminho que para para uma '
          'pessoa — se isso mudar, este cenário deixou de medir o que diz',
    );
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'o enchimento é uma promessa, e uma promessa quebrada tem de '
          'ser retirada: nada foi consertado',
    );
    closeTheRoom(container);
  });

  testWidgets('um upload que a sala recusou esvazia a faixa de novo', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester);
    expect(_faixasVazias(tester, container), isEmpty);
    harness.room.failReplaceWith = const RoomRefused();
    await _entregarATraducao(tester, container);

    expect(
      _faixasVazias(tester, container),
      [0],
      reason: 'a sala recusou o conserto, então ele não aconteceu',
    );
    closeTheRoom(container);
  });

  testWidgets('uma captura que a sala não aproveitou esvazia a faixa de novo', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester);
    expect(_faixasVazias(tester, container), isEmpty);
    harness.room.replaceCaptured = false;
    await _entregarATraducao(tester, container);

    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'a sala não fez nada com o que subiu — este ramo não recusa nem '
          'estoura, volta calado, e é o que faria a faixa dizer "consertado" '
          'sobre trabalho que não existe',
    );
  });

  testWidgets('uma parada que não devolveu arquivo esvazia a faixa de novo', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester);
    expect(_faixasVazias(tester, container), isEmpty);
    harness.recorder.returnsNothing = true;
    await _entregarATraducao(tester, container);

    expect(
      harness.room.replacesAsked,
      isEmpty,
      reason:
          'sem arquivo não há o que subir — se subir, este cenário deixou '
          'de medir uma falha',
    );
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'este ramo volta calado, sem parar para uma pessoa e sem contar '
          'a falha, e é justamente o que deixaria a promessa de pé sozinha',
    );
  });

  testWidgets('um microfone que não abriu não deixa a faixa cheia', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    harness.recorder.startThrows = true;
    await _escolherTraduzirDeNovo(tester);
    // The refused microphone put the team back on the rehearsal, so the second try
    // comes through the other door the short way has: the stretch tapped on the cord.
    await _notifier(
      container,
    ).traduzirDeNovo(container.read(salaSessionProvider).btTrechos.first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason:
          'gravador que não abriu duas vezes seguidas é o caminho que para '
          'para uma pessoa — se isso mudar, este cenário deixou de medir o que diz',
    );
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'a equipe se ofereceu para consertar e a sala não conseguiu '
          'ouvir: a faixa cheia prometeria um trabalho que o microfone nunca '
          'deixou começar',
    );
    closeTheRoom(container);
  });

  testWidgets('voltar a gravar depois do microfone recusado enche a faixa', (
    tester,
  ) async {
    final container = await _pumpToPergunta(tester);
    final harness = _harnessDaVez!;

    harness.recorder.startThrows = true;
    await _escolherTraduzirDeNovo(tester);
    expect(_faixasVazias(tester, container), [0]);

    harness.recorder.startThrows = false;
    // The halt is the desk's to lift, and the long press only asks: a facilitator
    // marks the session attended, and the touch brings that answer back at once.
    harness.room.theDeskAttended();
    _notifier(container).resolveWithPerson();
    await tester.pump(const Duration(milliseconds: 300));
    final capturasAntes = harness.recorder.captures;
    // The refused microphone put the team back on the rehearsal, so the way back into the
    // mend is the other door the short way has: the stretch tapped on the cord.
    await _notifier(
      container,
    ).traduzirDeNovo(container.read(salaSessionProvider).btTrechos.first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.recorder.captures,
      capturasAntes + 1,
      reason:
          'a pessoa veio e o toque volta a gravar — se não gravar, este '
          'cenário não chega ao que ele mede',
    );
    expect(
      _faixasVazias(tester, container),
      isEmpty,
      reason:
          'a promessa foi retirada quando o microfone recusou, e tem de '
          'ser feita outra vez agora que ele abriu: a equipe está gravando o '
          'conserto e a faixa não pode ficar vazia por cima disso',
    );
  });

  testWidgets('a sala que desistiu de esperar esvazia a faixa de novo', (
    tester,
  ) async {
    final container = await _pumpToPergunta(
      tester,
      teto: const Duration(seconds: 2),
    );
    final harness = _harnessDaVez!;

    await _escolherTraduzirDeNovo(tester);
    expect(_faixasVazias(tester, container), isEmpty);
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
      isTrue,
      reason:
          'o teto do estado ocupado para para uma pessoa — se isso mudar, '
          'este cenário deixou de medir o que diz',
    );
    expect(
      harness.room.replacesAsked,
      isEmpty,
      reason: 'e a gravação nunca chegou a subir',
    );
    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'é a falha sem nenhum outro sinal na tela: nada foi recusado, o '
          'círculo não está offline, só uma pessoa foi chamada. Se a faixa '
          'ficar cheia aqui, o colar diz que o conserto foi feito e é a única '
          'coisa que a equipe tem para ler',
    );

    harness.recorder.finishStop();
    await tester.pump(const Duration(milliseconds: 200));
    closeTheRoom(container);
  });

  testWidgets('um veredito que reprova o mesmo trecho esvazia a faixa de novo', (
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
    await _escolherTraduzirDeNovo(tester);
    await _entregarATraducao(tester, container);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    await _notifier(container).finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _faixasVazias(tester, container),
      [0],
      reason:
          'encher não é definitivo: o analista pode apontar o mesmo '
          'trecho outra vez, e a faixa volta a esperar conserto',
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

    await _escolherTraduzirDeNovo(tester);
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
