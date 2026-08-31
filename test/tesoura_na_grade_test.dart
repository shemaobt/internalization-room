import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const ouvirMaterna = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetro = 'Ouvir o contar em português';
const micMaterna = 'Regravar a voz na língua materna — refaz também o contar';
const micRetro = 'Recontar só em português';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

bool aceso(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled ?? false;

SalaHarness? harnessDaVez;

/// A team that told two stretches back and got a finding on the first, standing in front
/// of the question of where the error lives.
Future<ProviderContainer> pumpToPergunta(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFindingSegmentId = 'trecho-1';
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

/// Put the mother tongue in the air, which is the only state a cut can happen in.
Future<void> ouvindoAMaterna(WidgetTester tester) async {
  await tester.tap(byLabel(ouvirMaterna));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the team can divide a stretch they are hearing back',
      (tester) async {
    await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    await ouvindoAMaterna(tester);
    harness.playback.at = const Duration(seconds: 4);

    await tester.tap(byLabel(cortarTrechoLabel));
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.room.dividesAsked.length, 1,
        reason: 'o verbo de dividir existe e é testado desde a S2, e ninguém '
            'podia alcançá-lo: é a razão desta fatia');
  });

  testWidgets('the scissors is not there when there is nothing to cut',
      (tester) async {
    await pumpToPergunta(tester);

    expect(byLabel(cortarTrechoLabel), findsNothing,
        reason: 'cortar o que não se está ouvindo não tem ponto — o corte cai '
            'onde o áudio está, e sem áudio no ar não há onde');

    await ouvindoAMaterna(tester);

    expect(byLabel(cortarTrechoLabel), findsOneWidget,
        reason: 'o controle positivo: sem ele, uma tesoura que nunca aparece '
            'passaria por uma que aparece na hora certa');
  });

  testWidgets('the question still has two answers, and only two',
      (tester) async {
    await pumpToPergunta(tester);

    expect(aceso(tester, micMaterna), isTrue);
    expect(aceso(tester, micRetro), isTrue);
    expect(byLabel(cortarTrechoLabel), findsNothing,
        reason: 'com o som parado a pergunta está sendo feita, e ela tem duas '
            'respostas: a tesoura não pode estar aqui');

    await ouvindoAMaterna(tester);

    expect(byLabel(cortarTrechoLabel), findsOneWidget);
    expect(aceso(tester, micMaterna), isFalse,
        reason: 'e enquanto o som toca a pergunta não está sendo feita: a '
            'grade já mata os dois microfones, então a tesoura nunca divide a '
            'tela com as duas saídas');
    expect(aceso(tester, micRetro), isFalse);
  });

  testWidgets('after dividing, the team sees that something changed',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final harness = harnessDaVez!;
    await ouvindoAMaterna(tester);
    harness.playback.at = const Duration(seconds: 4);

    await tester.tap(byLabel(cortarTrechoLabel));
    await tester.pump(const Duration(milliseconds: 400));

    expect(byLabel(micMaterna), findsNothing,
        reason: 'o achado terminou, então a tela da pergunta sai — ficar '
            'igual ao que era antes do corte é a sala não responder');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing,
        reason: 'e a sala volta a pedir que contem, porque as duas metades '
            'nasceram sem explicação');
  });

  testWidgets('choosing a voice still works as it does today', (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micRetro));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
        reason: 'a grade e a tesoura não se atrapalham: escolher uma voz '
            'continua abrindo o microfone');
    expect(harnessDaVez!.room.dividesAsked, isEmpty);
  });
}
