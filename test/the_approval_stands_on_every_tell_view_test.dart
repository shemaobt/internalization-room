import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';

import 'a_wav_take.dart';
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
        terminar,
        tocar,
        tocarNoCirculo;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

Future<ProviderContainer> _conferidaPelaSala(
  WidgetTester tester,
  SalaHarness harness, {
  ApprovedDraft? aprovada,
}) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester);
  await contarAteOFimDaParte(tester, harness);
  harness.room
    ..readsChecked = true
    ..approvedDraft = aprovada;
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

  testWidgets('while a checked telling is checked again the approve button '
      'stays drawn but dimmed, and a check lost on the network leaves it lit', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);
    harness.room
      ..failFinishWith = const NetworkFailed('sem rede')
      ..holdNextVerdict();

    await tocar(tester, conferir);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.thinking);
    expect(
      byLabel(aprovar),
      findsOneWidget,
      reason:
          'durante a conferência de novo o botão sumia; o dela fica, apagado',
    );
    expect(_aprovarAceso(tester), isFalse);
    await _sala(container).aprovarRascunhoFinal();
    expect(harness.room.releasesAsked, isEmpty);

    harness.room.finishHeldVerdict();
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(_aprovarAceso(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('a check asked again that finds a part still unheard keeps the '
      'approve button, as hers keeps the passage conferida', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);

    await _conferidaDeNovoComUmaParteNaoOuvida(tester, harness, container);

    expect(
      byLabel(aprovar),
      findsOneWidget,
      reason:
          'a conferência que achava uma parte não ouvida tirava o botão; a '
          'dela não mexe na conferida da passagem',
    );
    expect(_aprovarAceso(tester), isTrue);
    closeTheRoom(container);
  });

  testWidgets('the approved badge stays on the check while its telling is '
      'checked again, not only at the verdict', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(
      tester,
      harness,
      aprovada: const ApprovedDraft(version: 1),
    );
    const selo = '✓ aprovado como rascunho final (v1)';
    expect(find.text(selo), findsOneWidget);
    expect(byLabel(aprovar), findsNothing);
    harness.room.holdNextVerdict();

    await tocar(tester, conferir);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.thinking);
    expect(
      find.text(selo),
      findsOneWidget,
      reason:
          'o selo só existia na fase conferida; o dela fica sempre que '
          'há uma versão aprovada',
    );
    harness.room.finishHeldVerdict();
    await tester.pump(const Duration(milliseconds: 600));
    closeTheRoom(container);
  });

  testWidgets('a frase told again over a checked telling takes the approve '
      'button away until the room checks it again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);

    _sala(container).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNoCirculo(tester);
    await tocar(tester, terminar);
    await waitFor(
      'a frase traduzida de novo assentar',
      () =>
          harness.room.replacesAsked.isNotEmpty &&
          container.read(salaSessionProvider).btPhase == BtPhase.playing,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.room.replacesAsked, hasLength(1));
    expect(
      byLabel(aprovar),
      findsNothing,
      reason:
          'o botão ficava sobre uma tradução que a sala ainda não conferiu; '
          'a dela deixa de ser conferida quando a frase é traduzida de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('a sentence recorded again over a checked telling takes the '
      'approve button away once it lands', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..readsChecked = true
      ..verdictNamedNuance = BtFinding(
        kind: BtFindingKind.nuance,
        frase: 3,
        segmentId: 'trecho-3',
      );
    await _sala(container).finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 600));
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(byLabel(aprovar), findsOneWidget);

    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocarNoCirculo(tester);
    harness.recorder.rehearsalSpeaks = aSpokenWav(
      length: const Duration(seconds: 2),
    );
    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(FraseList),
        matching: find.text('usar esta'),
      ),
    );
    await waitFor(
      'a frase regravada assentar',
      () =>
          harness.room.sentencesSent.isNotEmpty &&
          container.read(salaSessionProvider).btRegravacao == null,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      byLabel(aprovar),
      findsNothing,
      reason:
          'o botão ficava sobre uma frase nova que a sala ainda não '
          'conferiu; a dela deixa de ser conferida quando a frase assenta',
    );
    closeTheRoom(container);
  });

  testWidgets('a telling started over from a checked passage takes the '
      'approve button away', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);

    _sala(container).recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 700));
    _sala(container).recomecarATraducao();
    await waitFor(
      'a tradução recomeçar',
      () =>
          harness.room.restartsAsked.isNotEmpty &&
          container.read(salaSessionProvider).btPhase == BtPhase.playing,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      byLabel(aprovar),
      findsNothing,
      reason:
          'o botão ficava sobre uma tradução apagada; a dela lê a passagem '
          'de novo, e uma tradução recomeçada não é conferida',
    );
    closeTheRoom(container);
  });
}
