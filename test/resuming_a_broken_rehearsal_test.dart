import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show settle;

void main() {
  late Directory recordings;

  setUp(() => recordings = Directory.systemTemp.createTempSync('sala-ensaio'));
  tearDown(() => recordings.deleteSync(recursive: true));

  List<KeptTake> aRehearsalOfThreeParts() => [
        for (var part = 1; part <= 3; part++)
          KeptTake(
            scopeId: KeptScope.parte(part),
            path: (File('${recordings.path}/parte-$part.m4a')
                  ..writeAsBytesSync([1, 2, 3]))
                .path,
          ),
      ];

  Future<ProviderContainer> theyComeBackTo(
    SalaHarness harness,
    List<KeptTake> remembered,
  ) async {
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: remembered,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();
    return container;
  }

  test('coming back to a rehearsal with a part missing lands on the conversa', () async {
    final harness = SalaHarness();
    final remembered = aRehearsalOfThreeParts();
    File(remembered[1].path).deleteSync();

    final container = await theyComeBackTo(harness, remembered);

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.conversa,
        reason: 'duas partes de um ensaio de três voltavam como se fossem o ensaio da '
            'equipe, e a retrotradução era contada por cima de um buraco');
    expect(state.partes, isEmpty,
        reason: 'a sala não pode oferecer um ensaio que ela não tem inteiro');
    expect(File(remembered.first.path).existsSync(), isTrue,
        reason: 'o que a equipe gravou e sobreviveu continua no aparelho: recair na '
            'conversa é deixar de apresentar o ensaio, não apagá-lo');
  });

  test('coming back with every part still here restores the whole rehearsal', () async {
    final harness = SalaHarness();

    final container = await theyComeBackTo(harness, aRehearsalOfThreeParts());

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'com o ensaio inteiro em disco a equipe volta para onde parou');
    expect(state.partes, hasLength(3));
  });

  test('coming back with nothing left of the rehearsal still lands on the conversa',
      () async {
    final harness = SalaHarness();
    final remembered = aRehearsalOfThreeParts();
    for (final take in remembered) {
      File(take.path).deleteSync();
    }

    final container = await theyComeBackTo(harness, remembered);

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  test('the part recorded after coming back does not reuse a vanished number', () async {
    final harness = SalaHarness();
    final remembered = aRehearsalOfThreeParts();
    File(remembered.last.path).deleteSync();
    final container = await theyComeBackTo(harness, remembered);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();
    await harness.takes.flush();

    expect(harness.room.takesKept, ['ensaio/${KeptScope.parte(1)}'],
        reason: 'a parte nova era carimbada com o número da parte que sumiu, e o '
            'servidor recebia duas gravações diferentes com o mesmo rótulo');
  });
}
