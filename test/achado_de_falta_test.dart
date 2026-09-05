import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';

import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'retro_findings_exits_test.dart'
    show bySemanticsLabelWidget, wholeClipExit, reRecordExit;

/// The rehearsal told back once and handed to the analyst, stopping at the answer.
///
/// Its own copy rather than the one next door, which builds its own harness and does not
/// hand it back: these cases read what left the tablet for the room, and what the room's
/// voice played.
Future<ProviderContainer> ateOAchado(
  WidgetTester tester,
  SalaHarness harness,
  BtFindingKind? kind, {
  String? trecho,
}) async {
  harness.room
    ..verdictChecked = false
    ..verdictFinding = kind
    ..verdictFindingSegmentId = trecho;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  notifier.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// The one action a missing finding leaves standing.
///
/// The long way, not the short one: what is missing was probably left out of the
/// recording, not only out of the telling over it, so the mother tongue is recorded again
/// and the stretch told again over it — in that order, which is the only order the room
/// accepts.
const refazerParteExit = 'Regravar esta parte e contá-la de novo';

/// The question the room used to put, in the two labels that put it: which voice was
/// wrong. A stretch that is merely short has no answer to give either of them.
const escolherMaterna = micMaternaLabel;
const escolherRetro = micRetroLabel;

/// Every kind the analyst can send that is not a bare absence.
const outrosKinds = [
  BtFindingKind.addition,
  BtFindingKind.meaningChange,
  BtFindingKind.wrongRelation,
  BtFindingKind.reorderedEvent,
  BtFindingKind.preservationViolation,
  BtFindingKind.insufficientEvidence,
  BtFindingKind.unclear,
];

void main() {
  testWidgets('num achado de falta a sala não pergunta em qual voz mora o erro',
      (tester) async {
    await ateOAchado(tester, SalaHarness(filaEmMemoria: true),
        BtFindingKind.missing, trecho: 'trecho-1');

    expect(find.byType(OndeMoraGrade), findsNothing,
        reason: 'a pergunta não tem resposta possível: não houve erro em '
            'nenhuma das duas vozes, houve ausência');
    expect(bySemanticsLabelWidget(escolherMaterna), findsNothing);
    expect(bySemanticsLabelWidget(escolherRetro), findsNothing);
  });

  testWidgets('num achado de falta a saída é regravar aquela parte e contá-la de novo',
      (tester) async {
    final container = await ateOAchado(tester, SalaHarness(filaEmMemoria: true),
        BtFindingKind.missing, trecho: 'trecho-1');

    expect(bySemanticsLabelWidget(refazerParteExit), findsOneWidget);

    // Uma ação só. As outras duas saídas que a sala tem para um achado — recontar
    // a gravação inteira e regravar o clipe — não cabem aqui: o dono do produto
    // disse que não é a passagem toda e não é cortar trecho novo.
    expect(bySemanticsLabelWidget(wholeClipExit), findsNothing);
    expect(bySemanticsLabelWidget(reRecordExit), findsNothing);

    await tester.tap(bySemanticsLabelWidget(refazerParteExit));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(salaSessionProvider).btPhase, BtPhase.gravandoMaterna,
        reason: 'a saída abre a primeira das duas estações: a voz materna '
            'daquele trecho, gravada de novo');
  });

  testWidgets('os dois ouvires continuam na tela num achado de falta',
      (tester) async {
    await ateOAchado(tester, SalaHarness(filaEmMemoria: true),
        BtFindingKind.missing, trecho: 'trecho-1');

    expect(bySemanticsLabelWidget(ouvirMaternaLabel), findsOneWidget,
        reason: 'sem ouvir a própria voz a equipe não tem como saber o que '
            'faltou; ouvir não decide nada e nunca foi o defeito');
    expect(bySemanticsLabelWidget(ouvirRetroLabel), findsOneWidget);
  });

  testWidgets('o que sai para a sala é a sequência do caminho longo',
      (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await ateOAchado(
      tester,
      harness,
      BtFindingKind.missing,
      trecho: 'trecho-1',
    );
    final notifier = container.read(salaSessionProvider.notifier);

    await tester.tap(bySemanticsLabelWidget(refazerParteExit));
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.room.replacesAsked, isEmpty,
        reason: 'nada é substituído enquanto a voz nova não existe');

    // Primeira estação: a voz materna daquele trecho, gravada de novo.
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.retroTap();
    await letTheRehearsalReachTheRoom(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final novaGravacao = harness.room.takeIds.last;
    expect(harness.room.replacesSemArquivo, ['trecho-1'],
        reason: 'a voz nova sobe sozinha — mandá-la junto com a explicação '
            'velha é a combinação que o servidor recusa');

    // Segunda estação: contar aquele trecho de novo, sobre a voz que acabou de
    // entrar. Ela vem sozinha, sem a equipe pedir.
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, [
      'trecho-1@$novaGravacao:0-30000',
      'trecho-1-v1@$novaGravacao:0-30000',
    ], reason: 'as duas estações, nesta ordem, e as duas no mesmo endereço de '
        'áudio: a fatia inteira da gravação nova. O nome do trecho muda entre '
        'elas porque uma versão é uma linha nova e a sala aposenta a anterior — '
        'seguir o nome velho na segunda seria substituir um trecho que já não '
        'conta');
    expect(harness.room.chunksSent, 1,
        reason: 'o único chunk é o da retro original: as duas estações são '
            'substituições daquele trecho, e nenhuma delas corta trecho novo');
  });

  for (final kind in outrosKinds) {
    testWidgets('$kind continua exatamente como está', (tester) async {
      await ateOAchado(
          tester, SalaHarness(filaEmMemoria: true), kind, trecho: 'trecho-1');

      expect(find.byType(OndeMoraGrade), findsOneWidget,
          reason: 'é um erro numa das vozes, e a pergunta continua tendo '
              'resposta');
      expect(bySemanticsLabelWidget(escolherMaterna), findsOneWidget);
      expect(bySemanticsLabelWidget(escolherRetro), findsOneWidget);
      expect(bySemanticsLabelWidget(refazerParteExit), findsNothing);
    });
  }

  testWidgets('um achado de falta sem trecho nomeado cai no fallback de hoje',
      (tester) async {
    await ateOAchado(
        tester, SalaHarness(filaEmMemoria: true), BtFindingKind.missing);

    expect(find.byType(OndeMoraGrade), findsNothing);
    expect(bySemanticsLabelWidget(refazerParteExit), findsNothing,
        reason: 'sem endereço não há trecho a recontar; a sala volta ao que '
            'sempre fez');
    expect(bySemanticsLabelWidget(wholeClipExit), findsOneWidget);
    expect(bySemanticsLabelWidget(reRecordExit), findsOneWidget);
  });

  testWidgets('a sala não ganha nenhuma fala nova neste caminho', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await ateOAchado(
      tester,
      harness,
      BtFindingKind.missing,
      trecho: 'trecho-1',
    );
    final faladoAteAqui = List.of(harness.voice.assets);

    await tester.tap(bySemanticsLabelWidget(refazerParteExit));
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.voice.assets, faladoAteAqui,
        reason: 'a metade da fala — a sala dizer O QUE falta — é decisão de '
            'produto ainda aberta; esta fatia é só a ação na tela');
  });

  test('o vocabulário falado do app é o mesmo de antes desta fatia', () {
    expect(instantAckLines, ['F0', 'F1', 'F2', 'F3']);
    expect(inaudibleLines, ['D0', 'D1', 'D2']);
    expect(handoffLines, ['C0', 'C1']);
    expect(needsPersonLine, 'E0');
    expect(languages, ['pt', 'es', 'en']);
  });
}
