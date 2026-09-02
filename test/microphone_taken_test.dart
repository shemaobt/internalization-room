import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/eq_bars.dart';

import 'esperas.dart' show settle;
import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;

Future<void> _openTheMicrophone(
    WidgetTester tester, SalaSessionNotifier notifier) async {
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 120));
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  test('a call that takes the microphone is not a room that is still listening',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    await settle();
    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recording);

    harness.recorder.takeTheMicrophone();
    await settle();

    expect(container.read(salaSessionProvider).micTaken, isTrue,
        reason: 'o gravador avisava que tinha parado e ninguém escutava, então '
            'a máquina de estados seguia com a tomada aberta como se a equipe '
            'estivesse sendo gravada');

    harness.recorder.giveTheMicrophoneBack();
    await settle();

    expect(container.read(salaSessionProvider).micTaken, isFalse,
        reason: 'a tomada volta sozinha quando a ligação acaba, e uma sala que '
            'ficasse marcada de tomada nunca mais desenharia a captura');
  });

  testWidgets('the eq bars go still while another app holds the microphone',
      (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    await _openTheMicrophone(tester, container.read(salaSessionProvider.notifier));

    expect(tester.widget<EqBars>(find.byType(EqBars)).active, isTrue);

    harness.recorder.takeTheMicrophone();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<EqBars>(find.byType(EqBars)).active, isFalse,
        reason: 'as barras são o sinal mais forte de "o microfone está ligado" '
            'na tela do ensaio, e seguiam dançando sobre um gravador parado');

    harness.recorder.giveTheMicrophoneBack();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<EqBars>(find.byType(EqBars)).active, isTrue,
        reason: 'a captura volta quando a ligação acaba, e a tela tem de voltar '
            'com ela');
  });

  testWidgets('the record circle does not invite a recording that is already '
      'open', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    await _openTheMicrophone(tester, container.read(salaSessionProvider.notifier));

    harness.recorder.takeTheMicrophone();
    await tester.pump(const Duration(milliseconds: 200));

    expect(bySemanticsLabelWidget('Tocar ao terminar'), findsOneWidget,
        reason: 'a tomada continua aberta durante a ligação — o toque ainda é o '
            'que a encerra');
    expect(bySemanticsLabelWidget('Tocar para gravar o ensaio'), findsNothing,
        reason: 'apagar o halo pelo mesmo sinalizador que escolhe o rótulo '
            'convidaria a equipe a começar uma gravação que já está correndo');
  });
}
