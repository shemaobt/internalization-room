import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const micMaterna = 'Regravar a voz na língua materna — refaz também o contar';
const micRetro = 'Recontar só em português';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

SalaHarness? harnessDaVez;

SalaSessionNotifier notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// A team that told two stretches back and got a finding on the first, standing in front
/// of the question about which voice must speak again.
Future<ProviderContainer> pumpToPergunta(
  WidgetTester tester, {
  String apontado = 'trecho-1',
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.missing
    ..room.verdictFindingSegmentId = apontado;
  harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = notifier(container);
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

/// The first station: the team chooses the wood voice and records the mother tongue of
/// that stretch, tap to start and tap to stop.
Future<void> regravarONativo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(byLabel(micMaterna));
  await tester.pump(const Duration(milliseconds: 300));
  notifier(container).retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  notifier(container).retroTap();
  await letTheRehearsalReachTheRoom(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the new voice goes in and the old telling does not survive it',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;

    await regravarONativo(tester, container);

    // The stretch has a new name: a version is a new row, and the room retired the one the
    // finding came pointing at. The pointer moved with it, which is what this reads.
    final trecho = container.read(salaSessionProvider).btFindingTrecho!;
    expect(trecho.segmentId, isNot('trecho-1'),
        reason: 'seguir o nome antigo seria seguir um trecho que a sala já '
            'aposentou');
    expect(trecho.takeId, harness.room.takeIds.last,
        reason: 'o trecho passa a apontar para a gravação nova');
    expect(trecho.contado, isFalse,
        reason: 'e fica esperando ser contado: a explicação pertencia ao áudio '
            'que ninguém vai ouvir de novo');
    expect(trecho.retroPath, isNull,
        reason: 'inclusive a cópia local dela, que tocaria uma explicação que '
            'não vale mais');
    expect(harness.room.replacesSemArquivo, ['trecho-1'],
        reason: 'a voz nova sobe sozinha — mandá-la junto com a explicação '
            'velha é a combinação que o servidor recusa');
  });

  testWidgets('the new slice is the new recording, not the old stretch bounds',
      (tester) async {
    // The second stretch on purpose: it runs from 10s to 20s, so a slice claiming the old
    // bounds differs from the truthful one at both ends. On the first stretch, which
    // starts at nought, half the lie would be invisible.
    final container = await pumpToPergunta(tester, apontado: 'trecho-2');
    final harness = harnessDaVez!;
    harness.playback.measured = const Duration(seconds: 7);

    await regravarONativo(tester, container);

    expect(harness.playback.measurements, hasLength(1),
        reason: 'a duração é medida do arquivo novo, não suposta');
    expect(harness.room.replacesAsked, ['trecho-2@gravacao-2:0-7000'],
        reason: 'o take novo contém só aquele trecho, então ele vai de zero à '
            'própria duração. Alegar os limites do trecho antigo passaria no '
            'servidor — slice_moved já considera isso regravado — e apontaria '
            'para áudio que não existe naquele arquivo, que é a mentira que a '
            'sonda inteira existe para não precisar contar');
  });

  testWidgets('the second station comes on its own', (tester) async {
    final container = await pumpToPergunta(tester);

    await regravarONativo(tester, container);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
        reason: 'terminada a regravação a sala já abre o microfone para contar '
            'aquele trecho — a equipe não precisa pedir');
    expect(byLabel(micMaterna), findsNothing,
        reason: 'e não passa por escolha nenhuma: a pergunta já foi respondida');
    expect(byLabel(micRetro), findsNothing);
  });

  testWidgets('the order does not invert', (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.gravandoMaterna,
        reason: 'escolher a voz leva a regravar, não a contar');
    expect(harness.room.replacesAsked, isEmpty,
        reason: 'e nada é substituído enquanto a voz nova não existe');

    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    notifier(container).retroTap();
    await letTheRehearsalReachTheRoom(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.room.replacesSemArquivo, ['trecho-1'],
        reason: 'a voz nova é a primeira coisa a chegar ao servidor');
    expect(harness.room.replacesAsked.first, startsWith('trecho-1@'),
        reason: 'e o contar vem depois dela, nunca antes');
  });

  testWidgets('walking away between the stations does not leave the room mute',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;

    await regravarONativo(tester, container);
    harness.voice.played.clear();

    // The team walks off with the microphone open, and the retro is ended without the
    // stretch ever being told.
    harness.room.verdictChecked = false;
    harness.room.fixedLine = 'falta contar aquele trecho';
    await notifier(container).finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).btPhase,
        isNot(BtPhase.conferida),
        reason: 'a passagem não pode ser dada por conferida com um trecho que '
            'ninguém explicou');
    expect(harness.room.calls, contains('finishBackTranslation'),
        reason: 'e o portão da primeira rodada é consultado, que é quem fala');
  });

  testWidgets('the circle says what the touch does, at each end of the recording',
      (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Gravar este trecho'), findsOneWidget,
        reason: 'a estação existe para gravar, e agora ela grava — o rótulo '
            'provisório dizia "voltar" porque o passo não fazia o trabalho');

    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Tocar ao terminar a gravação'), findsOneWidget,
        reason: 'e o segundo toque encerra: tocar grava, tocar para');
  });

  testWidgets('a refused microphone leaves the touch meaning what it says',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    harness.recorder.startThrows = true;

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));
    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 300));

    // The recorder never started, so the room stopped for a person. A person comes.
    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    harness.recorder.startThrows = false;
    // The desk is what lifts a blocking halt now; the long press only asks the room
    // whether it has been lifted, which is what brings the team back at once.
    harness.room.theDeskAttended();
    notifier(container).resolveWithPerson();
    await tester.pump(const Duration(milliseconds: 300));

    final antes = harness.recorder.captures;
    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.captures, antes + 1,
        reason: 'nada estava gravando, então o toque grava — como o círculo '
            'promete. Guardar num sinalizador em vez de ler a voz fazia o '
            'toque seguinte encerrar uma gravação que nunca começou, e a '
            'equipe voltava à pergunta com o passo por fazer');
  });

  testWidgets('the short way stays short', (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    // The rehearsal's own take is already in there from the setup; what this scenario is
    // about is whether the short way adds another one.
    harness.room.takesKept.clear();

    await tester.tap(byLabel(micRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(harness.room.takesKept.where((k) => k.startsWith('ensaio')), isEmpty,
        reason: 'escolher só a tradução não grava voz nova em língua materna');
    expect(harness.playback.measurements, isEmpty,
        reason: 'nem mede duração de gravação nenhuma — não há gravação nova');
  });

  testWidgets('the neighbouring stretch does not move', (tester) async {
    final container = await pumpToPergunta(tester);
    final antes = container
        .read(salaSessionProvider)
        .btTrechos
        .firstWhere((t) => t.segmentId == 'trecho-2');

    await regravarONativo(tester, container);

    final depois = container
        .read(salaSessionProvider)
        .btTrechos
        .firstWhere((t) => t.segmentId == 'trecho-2');
    expect(depois.takeId, antes.takeId);
    expect(depois.from, antes.from);
    expect(depois.to, antes.to);
    expect(depois.contado, antes.contado,
        reason: 'correção é localizada — é a promessa do modelo inteiro, e é '
            'o que faz regravar um trecho não custar a passagem');
  });
}
