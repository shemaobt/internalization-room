import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aprovar,
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tocar,
        tocarNoCirculo;

Future<ProviderContainer> _conferidaPelaSala(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester);
  await contarAteOFimDaParte(tester, harness);
  harness.room.readsChecked = true;
  await tocar(tester, conferir);
  await tester.pump(const Duration(milliseconds: 600));
  expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
  expect(container.read(salaSessionProvider).btChecked, isTrue);
  return container;
}

Future<void> _conferidaDeNovoComUmaParteNaoOuvida(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final parte = container.read(salaSessionProvider).partes.single.takeId!;
  harness.room
    ..verdictRefusal = CheckRefusal.partUnheard
    ..verdictUnheardTakeIds = [parte]
    ..listeningUnheardTakeIds = [parte];
  await tocar(tester, conferir);
  await waitFor(
    'a sala dizer que falta ouvir',
    () =>
        container.read(salaSessionProvider).btRecusa ==
            CheckRefusal.partUnheard &&
        container.read(salaSessionProvider).btPhase == BtPhase.playing,
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 600));
  expect(container.read(salaSessionProvider).btClipEnded, isFalse);
}

SalaSessionNotifier _sala(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

bool _aprovarAceso(WidgetTester tester) {
  final enabled =
      tester.widget<Semantics>(byLabel(aprovar)).properties.enabled ?? true;
  final opacity = tester
      .widget<Opacity>(
        find.descendant(of: byLabel(aprovar), matching: find.byType(Opacity)),
      )
      .opacity;
  expect(
    enabled,
    opacity == 1,
    reason: 'o que a equipe vê aceso é o que o botão aceita',
  );
  return enabled;
}

void main() {
  testWidgets('a telling the room calls checked keeps the approve button while '
      'a frase is armed to be told again, not only at the verdict', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);

    _sala(container).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(
      byLabel(aprovar),
      findsOneWidget,
      reason:
          'o botão só existia na fase conferida; o dela fica em toda a vista '
          'de contar enquanto a sala diz conferida',
    );
    closeTheRoom(container);
  });

  testWidgets('the first listen of a checked passage offers no approval, as '
      'her listen step does not', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);
    harness.room.listeningUnheardTakeIds = [
      container.read(salaSessionProvider).partes.single.takeId!,
    ];

    _sala(container).leaveTheBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    _sala(container).startRetro();
    await waitFor(
      'a primeira escuta abrir',
      () => container.read(salaSessionProvider).btSoOuvir,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(container.read(salaSessionProvider).btSoOuvir, isTrue);
    expect(container.read(salaSessionProvider).btChecked, isTrue);
    expect(
      byLabel(aprovar),
      findsNothing,
      reason:
          'a sala conferida punha o botão de aprovar em cima da primeira '
          'escuta, que no dela é o passo de ouvir, sem aprovar',
    );
    closeTheRoom(container);
  });

  testWidgets('while the verdict is heard again the approve button stays '
      'drawn but dimmed, and a press asks the room for nothing', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);
    expect(_aprovarAceso(tester), isTrue);

    harness.voice.holdNextLine();
    _sala(container).ouvirARespostaDeNovo();
    await waitFor(
      'a resposta tocar de novo',
      () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(byLabel(aprovar), findsOneWidget);
    expect(
      _aprovarAceso(tester),
      isFalse,
      reason: 'com a voz falando o dela fica apagado; o nosso ficava aceso',
    );
    await _sala(container).aprovarRascunhoFinal();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      harness.room.releasesAsked,
      isEmpty,
      reason: 'a aprovação calava a voz e pedia a soltura por cima dela',
    );
    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 300));
    closeTheRoom(container);
  });

  testWidgets('while a frase told again is being recorded the approve button '
      'stays drawn but dimmed', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);

    _sala(container).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNoCirculo(tester);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(byLabel(aprovar), findsOneWidget);
    expect(
      _aprovarAceso(tester),
      isFalse,
      reason:
          'com o microfone aberto o dela fica apagado; o nosso ficava aceso',
    );
    closeTheRoom(container);
  });

  testWidgets('a press on the approve button away from the verdict approves, '
      'instead of doing nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);
    _sala(container).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(_aprovarAceso(tester), isTrue);

    await pressTheApproval(tester, aprovar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.releasesAsked,
      hasLength(1),
      reason: 'o botão aceso fora da conferida não pedia a soltura à sala',
    );
    expect(container.read(salaSessionProvider).ensaioSalvo, 1);
    closeTheRoom(container);
  });

  for (final (caso, texto, recusar)
      in <(String, String, void Function(FakeRoom))>[
        (
          'telling_back_not_checked',
          'para aprovar, a tradução precisa estar conferida',
          (room) => room.releaseBlockers = ['telling_back_not_checked'],
        ),
        (
          'an answer that approved nothing',
          'não deu para conferir agora — tentem de novo',
          (room) => room.release = const ApprovalAnswer(),
        ),
        (
          'a refused request',
          'não deu para conferir agora — tentem de novo',
          (room) => room.failReleaseWith = const Refused('CONFLICT'),
        ),
      ]) {
    testWidgets('a refused approval ($caso) only writes «$texto», and the '
        'check stays as it was, approve button and terminei lit', (
      tester,
    ) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _conferidaPelaSala(tester, harness);
      recusar(harness.room);
      final sons = harness.sounds.length;

      await pressTheApproval(tester, aprovar);
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text(texto), findsOneWidget);
      expect(
        container.read(salaSessionProvider).btPhase,
        BtPhase.conferida,
        reason: 'a recusa devolvia a tradução para antes do terminei',
      );
      expect(byLabel(aprovar), findsOneWidget);
      expect(
        _aprovarAceso(tester),
        isTrue,
        reason: 'o dela escreve o motivo e deixa o botão como estava',
      );
      expect(byLabel(conferir), findsOneWidget);
      expect(harness.sounds.skip(sons), isNot(contains('playback:play')));
      closeTheRoom(container);
    });
  }

  testWidgets('a refused approval while a part is still unheard leaves the '
      'terminei dimmed, not lit over what nobody heard', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);
    await _conferidaDeNovoComUmaParteNaoOuvida(tester, harness, container);
    harness.room.releaseBlockers = ['playback_did_not_cover_the_clip'];

    await pressTheApproval(tester, aprovar);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ainda falta ouvir um trecho da gravação'), findsWidgets);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(
      container.read(salaSessionProvider).canFinishBackTranslation,
      isFalse,
      reason:
          'a recusa dava o fim do clipe por ouvido e o terminei acendia por '
          'cima da parte que a sala ainda não ouviu',
    );
    closeTheRoom(container);
  });
}
