import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const blueMic = 'Gravar esta parte de novo';

Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// A team that rehearsed, told one stretch back, and had that stretch cut in two.
///
/// The two halves are born with nothing told about them, which is the situation the
/// room's gate stops on: the passage cannot be read while a stretch is still waiting.
/// Every step here is a verb the team has on the screen — nothing is written into the
/// session by hand.
Future<ProviderContainer> upToTwoUntoldHalves(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.missing
    ..verdictFindingSegmentId = 'trecho-1';

  final container = await pumpUpToAVerdict(tester, harness);
  final notifier = container.read(salaSessionProvider.notifier);

  notifier.ouvirVozMaterna();
  await tester.pump(const Duration(milliseconds: 200));
  harness.playback.at = const Duration(seconds: 5);
  await notifier.dividirTrecho();
  await tester.pump(const Duration(milliseconds: 300));

  harness.room
    ..verdictFinding = null
    ..verdictFindingSegmentId = null;
  return container;
}

void main() {
  testWidgets('a resposta do trecho não contado não apaga gravação nenhuma', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await upToTwoUntoldHalves(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    final antes = container.read(salaSessionProvider);
    final gravacoes = [for (final take in antes.keptTakes) take.takeId];
    expect(
      gravacoes,
      isNotEmpty,
      reason: 'o ensaio precisa existir para poder ser perdido',
    );

    harness.room.verdictUntoldSegmentId = 'trecho-1-a';
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 400));

    var depois = container.read(salaSessionProvider);
    expect([for (final take in depois.keptTakes) take.takeId], gravacoes);
    expect(depois.takes, antes.takes);
    expect(
      depois.stage,
      SalaStage.retro,
      reason:
          'a sala não volta ao ensaio por causa de uma explicação que faltou',
    );

    // A chegada da resposta nunca apagou nada por si. O que apagava era a única
    // saída para a frente que a tela oferecia depois dela: o microfone azul, que
    // recomeça o ensaio. Ela não pode estar ao alcance desta resposta.
    expect(
      byLabel(blueMic),
      findsNothing,
      reason:
          'a saída que zera as gravações não cabe num trecho que só falta '
          'ser contado, e estar na tela é estar ao alcance da equipe',
    );

    // E as tomadas seguem inteiras por todo o caminho que a sala abre daqui.
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 600));

    depois = container.read(salaSessionProvider);
    expect([for (final take in depois.keptTakes) take.takeId], gravacoes);
    expect(depois.takes, antes.takes);
  });

  testWidgets('a equipe é levada ao trecho nomeado, nos limites dele', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await upToTwoUntoldHalves(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final gravacao = container.read(salaSessionProvider).keptTakes.first.takeId;

    harness.room.verdictUntoldSegmentId = 'trecho-1-a';
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(salaSessionProvider).btTrechoTocando,
      isTrue,
      reason:
          'a sala toca a voz materna do trecho que falta, para a equipe '
          'saber qual é antes de contá-lo',
    );
    expect(
      harness.playback.ranges.last,
      '0-5000',
      reason:
          'os limites do trecho nomeado, não os da passagem inteira nem '
          'os do trecho vizinho',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    notifier.retroTap();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.replacesAsked,
      ['trecho-1-a@$gravacao:0-5000'],
      reason:
          'o que a equipe conta preenche o trecho nomeado, no endereço '
          'dele; um pedaço novo deixaria o trecho por contar e o portão '
          'pararia a passagem de novo',
    );
  });

  testWidgets(
    'um veredito comum com achado continua se comportando como hoje',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.verdictChecked = false
        ..room.verdictFinding = BtFindingKind.insufficientEvidence;
      final container = await pumpUpToAVerdict(tester, harness);

      expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
      expect(byLabel(blueMic), findsOneWidget);

      await tester.tap(byLabel(blueMic));
      await tester.pump(const Duration(milliseconds: 400));

      final depois = container.read(salaSessionProvider);
      expect(depois.stage, SalaStage.ensaio);
      expect(depois.takes, 0);
      expect(depois.keptTakes, isEmpty);
    },
  );

  testWidgets(
    'um endereço que o tablet não conhece pede uma pessoa e não apaga nada',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await upToTwoUntoldHalves(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      final antes = container.read(salaSessionProvider);
      final gravacoes = [for (final take in antes.keptTakes) take.takeId];

      harness.room.verdictUntoldSegmentId = 'trecho-que-este-tablet-nunca-viu';
      await notifier.finishBackTranslation();
      await tester.pump(const Duration(milliseconds: 400));

      final depois = container.read(salaSessionProvider);
      expect(
        depois.needsPerson,
        isTrue,
        reason:
            'um endereço sem tradução na lista do tablet é uma pessoa, não '
            'um recomeço',
      );
      expect([for (final take in depois.keptTakes) take.takeId], gravacoes);
      expect(depois.takes, antes.takes);
      expect(depois.stage, SalaStage.retro);
    },
  );

  testWidgets('uma resposta sem trecho não contado não muda nada', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await pumpUpToAVerdict(tester, harness);

    final depois = container.read(salaSessionProvider);
    expect(depois.btPhase, BtPhase.findings);
    expect(depois.btFindingTrecho?.segmentId, 'trecho-1');
    expect(depois.btTrechoTocando, isFalse);
    expect(depois.needsPerson, isFalse);
  });

  test('um servidor que não manda o campo não quebra o app', () {
    final antigo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'findings_remaining': 0,
    });
    expect(antigo.untoldSegmentId, isNull);

    final nulo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'untold_segment_id': null,
      'findings_remaining': 0,
    });
    expect(nulo.untoldSegmentId, isNull);

    final nomeado = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'untold_segment_id': 'trecho-7',
      'findings_remaining': 0,
    });
    expect(nomeado.untoldSegmentId, 'trecho-7');
  });
}

/// The rehearsal told back once and handed to the analyst, stopping at the answer.
Future<ProviderContainer> pumpUpToAVerdict(
  WidgetTester tester,
  SalaHarness harness,
) async {
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
