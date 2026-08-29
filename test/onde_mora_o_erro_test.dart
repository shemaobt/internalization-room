import 'package:flutter/material.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const ouvirMaterna = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetro = 'Ouvir o contar em português';
const micMaterna = 'Regravar a voz na língua materna — refaz também o contar';
const micRetro = 'Recontar só em português';
const contaApontada = 'Trecho apontado pelo analista';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

SalaHarness? harnessDaVez;

/// A team that told two stretches back and got a finding on the first.
Future<ProviderContainer> pumpToPergunta(
  WidgetTester tester, {
  BtFindingKind finding = BtFindingKind.missing,
  String? trecho = 'trecho-1',
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFinding = finding
    ..room.verdictFindingSegmentId = trecho;
  harnessDaVez = harness;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    notifier.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<void> _pumpGrade(WidgetTester tester, {required bool podeOuvirRetro}) =>
    tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: OndeMoraGrade(
            onOuvirMaterna: () {},
            onOuvirRetro: () {},
            onRegravarMaterna: () {},
            onRecontar: () {},
            podeOuvirRetro: podeOuvirRetro,
          ),
        ),
      ),
    ));

void main() {
  testWidgets('the blue player is dark when the tablet holds no telling',
      (tester) async {
    await _pumpGrade(tester, podeOuvirRetro: false);

    expect(tester.widget<Semantics>(byLabel(ouvirRetro)).properties.enabled,
        isFalse,
        reason: 'numa sessão retomada o contar existe no servidor e o arquivo '
            'não está aqui; um player aceso que responde com silêncio não tem '
            'como se explicar numa sala sem palavra escrita');
    expect(tester.widget<Semantics>(byLabel(micRetro)).properties.enabled,
        isTrue,
        reason: 'escolher não precisa do arquivo: a equipe sabe qual voz errou '
            'sem reouvi-la, e o contar novo é gravado do zero');
    expect(tester.widget<Semantics>(byLabel(ouvirMaterna)).properties.enabled,
        isTrue,
        reason: 'a voz de madeira é fatia do ensaio, que está no tablet');
  });

  testWidgets('both players are live when the tablet holds the telling',
      (tester) async {
    await _pumpGrade(tester, podeOuvirRetro: true);

    expect(tester.widget<Semantics>(byLabel(ouvirRetro)).properties.enabled,
        isTrue);
  });

  for (final kind in BtFindingKind.values) {
    testWidgets('both voices are offered when the finding is ${kind.name}',
        (tester) async {
      await pumpToPergunta(tester, finding: kind);

      expect(byLabel(micMaterna), findsOneWidget,
          reason: 'o tipo do achado decidia sozinho pela equipe, e três tipos '
              'escondiam a saída de recontar');
      expect(byLabel(micRetro), findsOneWidget);
      expect(byLabel(ouvirMaterna), findsOneWidget);
      expect(byLabel(ouvirRetro), findsOneWidget);
    });
  }

  testWidgets('choosing only the telling leaves the mother tongue untouched',
      (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.gravandoRetro,
        reason: 'só o contar escorregou, então é o contar que se refaz');
    expect(container.read(salaSessionProvider).stage, SalaStage.retro,
        reason: 'a gravação em língua materna daquele trecho não é tocada — '
            'sair para o ensaio seria refazê-la');
  });

  testWidgets('choosing the voice too records the mother tongue first',
      (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.gravandoMaterna,
        reason: 'a ordem é regra de produto e não sugestão: regravar o nativo '
            'implica sempre refazer o contar depois, nessa ordem');
    expect(container.read(salaSessionProvider).btPhase,
        isNot(BtPhase.gravandoRetro),
        reason: 'a equipe não pode ser levada a contar antes de ter regravado');
  });

  testWidgets('listening is free and decides nothing', (tester) async {
    final container = await pumpToPergunta(tester);

    final harness = harnessDaVez!;
    harness.playback.played.clear();

    await tester.tap(byLabel(ouvirMaterna));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings,
        reason: 'ouvir não é escolher — a equipe precisa poder comparar as '
            'duas vozes sem se comprometer com nenhuma');
    expect(harness.playback.ranges, isNotEmpty,
        reason: 'e ouvir tem de ouvir: o player de madeira toca a fatia da '
            'gravação em língua materna');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.played.clear();

    await tester.tap(byLabel(ouvirRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(harness.playback.played, isNotEmpty,
        reason: 'o player azul toca o contar em português daquele trecho — '
            'sem isso a equipe compara uma voz com o silêncio');
  });

  for (final kind in [BtFindingKind.missing, BtFindingKind.addition]) {
    testWidgets(
        'a ${kind.name} finding that names no stretch still falls to the whole '
        'thing', (tester) async {
      final container = await pumpToPergunta(
        tester,
        finding: kind,
        trecho: null,
      );

      expect(byLabel(micMaterna), findsNothing,
          reason: 'sem trecho apontado não há o que substituir, e a grade '
              'pergunta sobre um trecho');
      expect(byLabel(micRetro), findsNothing);
      expect(container.read(salaSessionProvider).btPhase, BtPhase.findings,
          reason: 'o caminho de hoje para achado sem ponteiro não muda — e '
              'isso inclui o tipo continuar governando a queda, que é a '
              'única coisa que ele ainda governa');
    });
  }

  testWidgets('the pointed stretch is told apart from the others',
      (tester) async {
    await pumpToPergunta(tester);

    expect(byLabel(contaApontada), findsOneWidget,
        reason: 'a sala não tem texto na tela, então a equipe só descobre onde '
            'está o problema se a conta daquele trecho se distinguir');
  });
}
