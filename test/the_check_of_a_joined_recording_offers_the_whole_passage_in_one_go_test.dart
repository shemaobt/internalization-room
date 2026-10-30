import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/presentation/widgets/grain_choice_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show
        byLabel,
        holdTheSession,
        intoTheBackTranslation,
        voiceOverFocusLeaves,
        voiceOverTap;

const _wholeAtOnce = 'gravar a passagem inteira de uma vez';
const _recordThePart = 'voltar e regravar uma parte';
const _wholeArmed = 'toquem de novo: as cenas e as traduções ficam guardadas';
const _reopenArmed = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _theArmLapses = Duration(seconds: 8);
const _whole = 'A passagem inteira';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';

Future<void> _settles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await _passo(tester);
  }
}

bool? _aberto(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await _passo(tester);
}

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _naConferencia(
  WidgetTester tester,
  SalaHarness harness, {
  bool juntada = true,
  bool aprovada = false,
  bool conferida = false,
  bool primeiraEscuta = false,
  bool aPrimeiraParteContada = true,
  String lingua = 'pt',
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1876');
  addTearDown(() => pasta.deleteSync(recursive: true));
  await holdTheSession(
    harness,
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        for (final n in [1, 2])
          KeptTake(
            scopeId: KeptScope.parte(n),
            path: (File(
              '${pasta.path}/p$n.wav',
            )..writeAsBytesSync([1, 2, 3])).path,
            takeId: 'gravacao-$n',
            origin: juntada ? 'ensaio-da-cena-$n' : null,
          ),
      ],
    ),
    language: lingua,
  );
  harness.room.takes.addAll([
    for (final n in [1, 2])
      TakeView(
        takeId: 'gravacao-$n',
        kind: 'ensaio',
        scope: KeptScope.parte(n),
        ordinal: n,
        pass: 1,
        origin: juntada ? 'ensaio-da-cena-$n' : null,
      ),
  ]);
  if (aprovada) harness.room.approvedDraft = const ApprovedDraft(version: 1);
  if (primeiraEscuta) {
    harness.room.listeningUnheardTakeIds = const ['gravacao-1', 'gravacao-2'];
  }
  harness.room.retroSoFar = BackTranslationProgress(
    checked: aprovada || conferida,
    segments: [
      if (!primeiraEscuta && aPrimeiraParteContada)
        const SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 5000,
          frase: 1,
        ),
      if (!primeiraEscuta)
        const SegmentView(
          segmentId: 'trecho-2',
          takeId: 'gravacao-2',
          startsMs: 0,
          endsMs: 5000,
          frase: 2,
        ),
    ],
  );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  if (!aprovada) {
    await intoTheBackTranslation(
      container.read(salaSessionProvider.notifier),
      () => container.read(salaSessionProvider),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
  } else {
    SalaSessionState estado() => container.read(salaSessionProvider);
    await waitFor(
      'a passagem aprovada pousar na conversa',
      () => estado().stage == SalaStage.conversa && !estado().awaitingTheGuide,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
    await waitFor(
      'a casa da gravação abrir',
      () => estado().stage == SalaStage.ensaio && estado().partes.isNotEmpty,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    container.read(salaSessionProvider.notifier).startRetro();
  }
  await waitFor(
    'a conferência voltar com as duas frases',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        primeiraEscuta == container.read(salaSessionProvider).btSoOuvir &&
        container.read(salaSessionProvider).btTrechos.length ==
            (primeiraEscuta ? 0 : (aPrimeiraParteContada ? 2 : 1)) &&
        container.read(salaSessionProvider).btPhase ==
            (aprovada || conferida ? BtPhase.conferida : BtPhase.playing),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await waitFor(
    'a conferência ficar em silêncio',
    () => !harness.playback.sounding,
    step: () async {
      harness.playback.finishPlayback();
      await _passo(tester);
    },
  );
  await _passo(tester);
  return container;
}

Future<void> _umVeredito(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await waitFor(
    'a gravação tocar até o fim',
    () => container.read(salaSessionProvider).btClipEnded,
    step: () async {
      harness.playback.finishPlayback();
      await _passo(tester);
    },
  );
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 1
    ..verdictFindings = const [
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
    ];
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar com o achado',
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.playing &&
        container.read(salaSessionProvider).btVeredito,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

void main() {
  testWidgets('the check of a joined recording offers «gravar a passagem '
      'inteira de uma vez» in the telling step', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    expect(
      find.text(_wholeAtOnce),
      findsOneWidget,
      reason:
          'a conferência do Ensaio Final não oferecia gravar a passagem '
          'de uma vez, e a dela oferece',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict it sits under «voltar e regravar uma parte», '
      'as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    await _umVeredito(tester, harness, container);

    expect(find.text(_recordThePart), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_wholeAtOnce)).dy,
      greaterThan(tester.getTopLeft(find.text(_recordThePart)).dy),
      reason: 'o dela fica logo abaixo de voltar e regravar uma parte',
    );
    closeTheRoom(container);
  });

  testWidgets('the check of a joined recording offers it in english as '
      '«record the whole passage in one go»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _naConferencia(tester, harness, lingua: 'en');

    expect(
      find.text('record the whole passage in one go'),
      findsOneWidget,
      reason: 'em inglês a conferência não tinha as palavras dela',
    );
    closeTheRoom(container);
  });

  testWidgets('the first tap arms it with «toquem de novo: as cenas e as '
      'traduções ficam guardadas»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    await _tap(tester, _wholeAtOnce);

    expect(
      find.text(_wholeArmed),
      findsOneWidget,
      reason: 'o primeiro toque não armava, e o dela diz o que fica guardado',
    );
    expect(harness.room.grainSwitches, isEmpty);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('a VoiceOver double-tap arms it, and asleep it offers no tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    voiceOverTap(tester, _wholeAtOnce);
    await _passo(tester);

    expect(
      find.text(_wholeArmed),
      findsOneWidget,
      reason: 'o VoiceOver anunciava o botão e o toque duplo não armava nada',
    );
    expect(
      tester.getSemantics(byLabel(_wholeArmed)),
      isSemantics(hasTapAction: false),
      reason: 'o botão armado ainda dormindo oferecia o toque ao leitor',
    );
    expect(harness.room.grainSwitches, isEmpty);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('VoiceOver hears it not pressed before the first tap and '
      'pressed while it is armed, as hers', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    expect(
      tester.getSemantics(byLabel(_wholeAtOnce)),
      isSemantics(hasToggledState: true, isToggled: false),
      reason: 'o VoiceOver não sabia que o botão arma antes de trocar',
    );

    await _tap(tester, _wholeAtOnce);

    expect(
      tester.getSemantics(byLabel(_wholeArmed)),
      isSemantics(hasToggledState: true, isToggled: true),
      reason: 'o botão armado soava solto para o VoiceOver',
    );
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('armed, VoiceOver focus leaving it reads «gravar a passagem '
      'inteira de uma vez» again, and the next tap only arms', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(_wholeArmed), findsOneWidget);

    voiceOverFocusLeaves(tester, byLabel(_wholeArmed));
    await _passo(tester);

    expect(
      find.text(_wholeAtOnce),
      findsOneWidget,
      reason: 'o botão seguia armado depois que o foco do VoiceOver saiu dele',
    );
    expect(find.text(_wholeArmed), findsNothing);

    await _tap(tester, _wholeAtOnce);

    expect(find.text(_wholeArmed), findsOneWidget);
    expect(
      harness.room.grainSwitches,
      isEmpty,
      reason: 'o toque seguinte trocava o grão em vez de só armar',
    );
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('in english the armed text reads «tap again: the scenes and the '
      'translations are kept»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _naConferencia(tester, harness, lingua: 'en');

    await _tap(tester, 'record the whole passage in one go');

    expect(
      find.text('tap again: the scenes and the translations are kept'),
      findsOneWidget,
    );
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('over an approved draft the first tap arms with «toquem de '
      'novo: isto abre de novo o rascunho aprovado»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, aprovada: true);

    await _tap(tester, _wholeAtOnce);

    expect(
      find.text(_reopenArmed),
      findsOneWidget,
      reason: 'sobre o rascunho aprovado o dela avisa que abre de novo',
    );
    expect(harness.room.grainSwitches, isEmpty);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('a second tap 2 s later switches the grain through the room\'s '
      'door and lands on the whole-passage home', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    await _settles(tester);

    expect(harness.room.grainSwitches, [(grain: Grain.whole, reopens: false)]);
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'a troca acontecia e a equipe ficava na conferência',
    );
    expect(find.text(_homeLine), findsOneWidget);
    expect(find.text(_whole), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('over an approved draft the second tap switches with the reopen '
      'and lands on the whole-passage home', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, aprovada: true);

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _reopenArmed);
    await _settles(tester);

    expect(
      harness.room.grainSwitches,
      [(grain: Grain.whole, reopens: true)],
      reason: 'sem a reabertura a sala recusa a troca sobre o aprovado',
    );
    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(find.text(_homeLine), findsOneWidget);
    expect(find.text(_whole), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a check no join touched never offers it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, juntada: false);

    expect(
      find.text(_wholeAtOnce),
      findsNothing,
      reason: 'o dela só aparece sobre uma gravação juntada',
    );
    closeTheRoom(container);
  });

  testWidgets('the first listen of a joined recording, before the telling, '
      'never offers it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(
      tester,
      harness,
      primeiraEscuta: true,
    );

    expect(
      find.text(_wholeAtOnce),
      findsNothing,
      reason: 'o dela só aparece no passo de traduzir, não na primeira escuta',
    );
    closeTheRoom(container);
  });

  testWidgets('while a part sounds it is dimmed and a tap does not arm it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
    await _passo(tester);
    expect(harness.playback.sounding, isTrue);

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto algo soa',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the guide speaks it is dimmed and a tap does not arm it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    await _umVeredito(tester, harness, container);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    harness.voice.holdNextLine();
    await _tap(tester, 'ouvir a resposta de novo');
    expect(container.read(salaSessionProvider).channel, isA<GuideSpeaking>());

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto a voz fala',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    harness.voice.finishHeldLine();
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the check is sent and its verdict awaited it is dimmed '
      'and a tap does not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    harness.room.holdNextVerdict();
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.thinking);

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto a conferência é enviada',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    harness.room.finishHeldVerdict();
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while a sentence re-record is open it is dimmed and a tap does '
      'not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    await _tap(tester, 'regravar a frase 1');
    await waitFor(
      'a frase tocar até o fim',
      () => !harness.playback.sounding,
      step: () async {
        harness.playback.finishPlayback();
        await _passo(tester);
      },
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).btRegravacao, isNotNull);
    expect(container.read(salaSessionProvider).channel, isA<Silence>());

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto uma frase é regravada',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the approval is on its way to the room it is dimmed and '
      'a tap does not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, conferida: true);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    harness.room.holdNextRelease();
    unawaited(
      container.read(salaSessionProvider.notifier).aprovarRascunhoFinal(),
    );
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).aBackTranslationGestureActs,
      isFalse,
    );

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto a aprovação vai para a sala',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    harness.room.finishHeldRelease();
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the switch is in the air more taps never call the door '
      'again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    harness.room.holdTheGrainSwitch();

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    expect(container.read(salaSessionProvider).grainSwitching, isTrue);

    for (var vez = 0; vez < 2; vez++) {
      container.read(salaSessionProvider.notifier).recordTheWholePassage();
      await tester.pump(const Duration(seconds: 2));
    }

    expect(
      harness.room.grainSwitches,
      hasLength(1),
      reason: 'um toque durante a troca chamava a porta da sala de novo',
    );
    harness.room.finishTheGrainSwitch();
    await _settles(tester);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('a halt raised on the back-translation\'s check leaves the '
      'switch lit and a tap arms it, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await _passo(tester);
    expect(container.read(salaSessionProvider).needsPerson, isFalse);

    expect(
      _aberto(tester, _wholeAtOnce),
      isTrue,
      reason: 'a parada apagava a troca, e a dela segue acesa',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsOneWidget);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('a tap that reaches the room while a part sounds never arms '
      'the switch, even before the screen dims it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.ouvirOTrechoContado(0);
    notifier.recordTheWholePassage();
    await _passo(tester);
    expect(harness.playback.sounding, isTrue);

    expect(
      container.read(salaSessionProvider).armedTap,
      isNull,
      reason: 'o toque que chegava antes de a tela apagar o botão ainda armava',
    );
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('the second tap leaves the check at once, as hers: while the '
      'door is in the air the circle opens no microphone', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    harness.room.holdTheGrainSwitch();

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    expect(container.read(salaSessionProvider).grainSwitching, isTrue);

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'a conferência seguia aberta enquanto a troca ia para a sala',
    );
    final capturas = harness.recorder.captures;
    container.read(salaSessionProvider.notifier).retroTap();
    await _passo(tester);
    expect(
      harness.recorder.captures,
      capturas,
      reason: 'uma frase contada durante a troca era jogada fora na chegada',
    );
    harness.room.finishTheGrainSwitch();
    await _settles(tester);
    closeTheRoom(container);
  });

  testWidgets('a door that refuses leaves the team on the recording home with '
      'its joined parts, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    harness.room.grainAnswersFirst.add(const Refused(RefusalCode.notFound));

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    await _settles(tester);

    expect(harness.room.grainSwitches, hasLength(1));
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'o dela sai da conferência no toque, antes da resposta da sala',
    );
    expect(container.read(salaSessionProvider).recordsTheWhole, isFalse);
    expect(container.read(salaSessionProvider).partes, hasLength(2));
    closeTheRoom(container);
  });

  testWidgets('on a joined check, what was heard reaches the room before the '
      'grain door, through the armed taps', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    final relatos = harness.room.listeningReports.length;
    harness.room.holdTheGrainSwitch();

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    expect(harness.room.grainSwitches, hasLength(1));

    expect(
      [
        for (final relato in harness.room.listeningReports.skip(relatos))
          for (final parte in relato)
            '${parte['take_id']} ${parte['played_ranges']}',
      ],
      ['gravacao-1 [[0, 5000]]', 'gravacao-2 [[0, 5000]]'],
      reason:
          'a troca tirava as partes antes do relato, e o que soou na '
          'conferência nunca chegava à sala',
    );
    harness.room.finishTheGrainSwitch();
    await _settles(tester);
    closeTheRoom(container);
  });

  testWidgets('a tap that reaches the room on a check no join touched never '
      'switches the grain', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, juntada: false);

    container.read(salaSessionProvider.notifier).recordTheWholePassage();
    await _settles(tester);

    expect(
      harness.room.grainSwitches,
      isEmpty,
      reason: 'a sala aceitava a troca num estado que a tela nunca desenha',
    );
    expect(container.read(salaSessionProvider).stage, SalaStage.retro);
    closeTheRoom(container);
  });

  testWidgets('a tap that reaches the room during the first listen never arms '
      'the switch', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(
      tester,
      harness,
      primeiraEscuta: true,
    );

    container.read(salaSessionProvider.notifier).recordTheWholePassage();
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).armedTap,
      isNull,
      reason: 'a troca armava na primeira escuta, onde a tela não a oferece',
    );
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('on the check its own rule decides whether it rests, never the '
      'home\'s rule of what may start', (tester) async {
    const naCasa = SalaSessionState(grainSwitching: true);
    expect(naCasa.nothingStartsNow, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: wholeAtOnce(naCasa, 'pt', () {}, open: true),
      ),
    );

    expect(
      _aberto(tester, _wholeAtOnce),
      isTrue,
      reason:
          'uma parte subindo apagava o botão na conferência, sem palavra '
          'que explicasse; o dela só descansa pelo que a conferência faz',
    );
  });

  testWidgets('on a joined recording «terminei» stays dimmed while a part has '
      'no frase told, though the room counts every part heard, and a tap '
      'sends no check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.listeningUnheardTakeIds = const [];
    final container = await _naConferencia(
      tester,
      harness,
      aPrimeiraParteContada: false,
    );
    await _passo(tester);
    container.read(salaSessionProvider.notifier).ouvirGravacao();
    await waitFor(
      'a gravação tocar até o fim',
      () => container.read(salaSessionProvider).btClipEnded,
      step: () async {
        harness.playback.finishPlayback();
        await _passo(tester);
      },
    );
    await _passo(tester);

    expect(
      _aberto(tester, 'terminei'),
      isFalse,
      reason:
          'uma frase na segunda cena acendia o terminei com a primeira sem '
          'tradução, e o dela espera uma frase em cada cena',
    );
    await tester.tap(byLabel('terminei'));
    await _passo(tester);
    expect(
      harness.room.playedByTakeSent,
      isEmpty,
      reason: 'o toque pedia uma conferência que a sala recusa',
    );
    closeTheRoom(container);
  });

  testWidgets('on a joined recording with a frase told on every part and the '
      'room counting every part heard «terminei» is lit, and a tap sends the '
      'check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.listeningUnheardTakeIds = const [];
    final container = await _naConferencia(tester, harness);
    await _passo(tester);
    container.read(salaSessionProvider.notifier).ouvirGravacao();
    await waitFor(
      'a gravação tocar até o fim',
      () => container.read(salaSessionProvider).btClipEnded,
      step: () async {
        harness.playback.finishPlayback();
        await _passo(tester);
      },
    );
    await _passo(tester);

    expect(_aberto(tester, 'terminei'), isTrue);
    await tester.tap(byLabel('terminei'));
    await waitFor(
      'a conferência chegar à sala',
      () => harness.room.playedByTakeSent.isNotEmpty,
      step: () => _passo(tester),
    );
    expect(harness.room.playedByTakeSent, hasLength(1));
    closeTheRoom(container);
  });
}
