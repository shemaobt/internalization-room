import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const _gravacao = 'gravacao-1';
const _sessao = 'sessao-antiga';
const _linha = 'Ruth/P01';

const _checagem = 'Checagem externa';
const _novoOuvinte = 'Novo ouvinte';
const _voltar = 'Voltar para a gravação';
const _circulo = 'Toque para contar o que ouviu';
const _contem = 'Contem, do jeito de vocês, o que ouviram.';
const _agradecemos = 'Agradecemos sua ajuda.';
const _outroOuvinte = 'Outro ouvinte';
const _terminarAChecagem = 'Terminar a checagem';
const _visto = '✓';
const _naoAbriu = 'não deu para abrir a checagem externa — tentem de novo';
const _ouvirDeNovo = 'ouvir de novo';

const _checked = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: _gravacao,
      startsMs: 0,
      endsMs: 12000,
    ),
  ],
  checked: true,
);

final _aParte = Uint8List.fromList(utf8.encode('a parte aprovada ' * 40));
final _reconto = Uint8List.fromList(List.generate(4000, (i) => i % 251));

typedef _Tablet = ({SalaHarness harness, ProviderContainer container});

SalaHarness _umTablet({
  FakeRoom? room,
  WorkInProgress? disco,
  String lingua = testLanguage,
}) {
  final harness =
      SalaHarness(
          filaEmMemoria: true,
          room: room,
          emAbertoNoDisco: disco,
          lingua: lingua,
        )
        ..playback.length = const Duration(seconds: 30)
        ..playback.measured = const Duration(seconds: 30);
  harness.recorder
    ..rehearsalSpeaks = _reconto
    ..rehearsalSpeaksAs = 'm4a';
  return harness;
}

/// A room holding the passage's approved draft over its one part, and a tablet whose
/// resume point stands on [stage], naming [ouvinte] when it is set.
SalaHarness _aprovadaNaSala({
  SalaStage stage = SalaStage.retro,
  ({int version, int number})? ouvinte,
  String lingua = testLanguage,
}) {
  final harness = _umTablet(lingua: lingua);
  harness.room
    ..approvedDraft = const ApprovedDraft(version: 1)
    ..createdOpened = true
    ..retroSoFar = _checked
    ..takes.add(
      const TakeView(
        takeId: _gravacao,
        kind: 'ensaio',
        scope: 'parte-1',
        ordinal: 1,
      ),
    )
    ..takeAudio[_gravacao] = _aParte
    ..checkTakes = const [_gravacao];
  _naLinha(harness, stage: stage, ouvinte: ouvinte);
  return harness;
}

void _naLinha(
  SalaHarness harness, {
  SalaStage stage = SalaStage.retro,
  ({int version, int number})? ouvinte,
}) {
  final home = Directory.systemTemp.createTempSync('sala-ouvinte');
  addTearDown(() => home.deleteSync(recursive: true));
  harness.emAberto.rows['$_linha/${harness.lingua}'] = ResumePoint(
    sessionId: _sessao,
    stage: stage,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File('${home.path}/p1.m4a')..writeAsBytesSync([1])).path,
        takeId: _gravacao,
      ),
    ],
    listener: ouvinte,
  );
}

Future<_Tablet> _abrir(
  WidgetTester tester,
  SalaHarness harness, {
  bool pelaBolinha = true,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late ProviderContainer container;
  await tester.runAsync(() async {
    container = harness.container();
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await Future<void>.delayed(const Duration(seconds: 1));
    if (pelaBolinha) notifier.openTheEnsaioFinal();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passar(tester);
  return (harness: harness, container: container);
}

/// Kill the tablet and launch it again over the same disk and the same room.
Future<_Tablet> _relancar(
  WidgetTester tester,
  _Tablet tablet, {
  bool pelaBolinha = true,
}) async {
  await tester.pumpWidget(const SizedBox());
  tablet.container.dispose();
  final again = _umTablet(
    room: tablet.harness.room,
    disco: tablet.harness.emAbertoNoDisco ?? tablet.harness.emAberto,
    lingua: tablet.harness.lingua!,
  );
  final next = await _abrir(tester, again, pelaBolinha: pelaBolinha);
  addTearDown(next.container.dispose);
  return next;
}

/// Closes the tablet while the passage still plays, before the binding counts its timers.
Future<void> _fechar(WidgetTester tester, _Tablet tablet) async {
  await tester.pumpWidget(const SizedBox());
  tablet.container.dispose();
}

Future<_Tablet> _aberta(WidgetTester tester, SalaHarness harness) async {
  final tablet = await _abrir(tester, harness);
  addTearDown(tablet.container.dispose);
  return tablet;
}

SalaSessionState _sala(_Tablet tablet) =>
    tablet.container.read(salaSessionProvider);

Future<void> _passar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tocar(WidgetTester tester, String label) async {
  await tester.ensureVisible(byLabel(label).first);
  await tester.tap(byLabel(label).first, warnIfMissed: false);
  await _passar(tester);
}

List<(String, String)> _falasX(SalaHarness harness) => [
  for (final line in harness.voice.fixedLines)
    if (line.$1.startsWith('X')) line,
];

bool? _habilitado(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

Future<void> _entrarDeNovo(WidgetTester tester, _Tablet tablet) async {
  await tester.runAsync(() async {
    final notifier = tablet.container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  await _passar(tester);
}

int _gravacoes(SalaHarness harness) =>
    harness.sounds.where((sound) => sound == 'recorder:start').length;

/// «Novo ouvinte» or «Outro ouvinte» tapped: the next listener hears the passage and
/// stands at the retelling.
Future<void> _ouveAPassagem(WidgetTester tester, _Tablet tablet) async {
  tablet.harness.playback.finishPlayback();
  await _passar(tester);
  expect(find.text(_contem), findsOneWidget);
}

Future<void> _reconta(WidgetTester tester) async {
  await _tocar(tester, _circulo);
  await _tocar(tester, _circulo);
}

Future<_Tablet> _noReconto(WidgetTester tester, SalaHarness harness) async {
  final tablet = await _aberta(tester, harness);
  await _tocar(tester, _checagem);
  await _tocar(tester, _novoOuvinte);
  await _ouveAPassagem(tester, tablet);
  return tablet;
}

Future<_Tablet> _noAgradecimento(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final tablet = await _noReconto(tester, harness);
  await _reconta(tester);
  return tablet;
}

void _oAgradecimento({
  String agradecemos = _agradecemos,
  String outro = _outroOuvinte,
  String terminar = _terminarAChecagem,
}) {
  expect(find.text(_visto), findsOneWidget);
  expect(find.text(agradecemos), findsOneWidget);
  expect(byLabel(outro), findsOneWidget);
  expect(byLabel(terminar), findsOneWidget);
  expect(byLabel(_circulo), findsNothing);
}

void main() {
  testWidgets('once the retelling lands, her thanks is said and the end screen '
      'shows; the listener is finished, complete', (tester) async {
    final harness = _aprovadaNaSala();
    await _noReconto(tester, harness);

    await _reconta(tester);

    expect(_falasX(harness).last, ('X4', 'pt'));
    _oAgradecimento();
    expect(harness.room.listenersFinished, [
      (version: 1, number: 1, completed: true),
    ]);
    expect(harness.room.listenerRecordings.map((r) => r.kind), ['retell']);
  });

  testWidgets('«Outro ouvinte» starts the next number at X-open, and the one '
      'before is finished once', (tester) async {
    final harness = _aprovadaNaSala();
    final tablet = await _noAgradecimento(tester, harness);
    await _tocar(tester, _outroOuvinte);
    await _ouveAPassagem(tester, tablet);
    await _reconta(tester);
    final tocadas = harness.playback.played.length;

    await _tocar(tester, _outroOuvinte);

    expect(harness.room.listenersAsked, hasLength(3));
    expect(find.text('ouvinte 3'), findsOneWidget);
    expect(_falasX(harness).last, ('X0', 'pt'));
    expect(harness.playback.played.length, greaterThan(tocadas));
    expect(
      harness.room.listenersFinished.where((finish) => finish.number == 2),
      hasLength(1),
    );
    await _fechar(tester, tablet);
  });

  testWidgets('«Terminar a checagem» after three listeners shows «checagem '
      'externa: 3 ouvintes» on the recording home', (tester) async {
    final harness = _aprovadaNaSala();
    final tablet = await _noAgradecimento(tester, harness);
    for (var i = 0; i < 2; i++) {
      await _tocar(tester, _outroOuvinte);
      await _ouveAPassagem(tester, tablet);
      await _reconta(tester);
    }
    harness.room.approvedDraft = const ApprovedDraft(version: 1, listeners: 3);

    await _tocar(tester, _terminarAChecagem);

    expect(_sala(tablet).stage, SalaStage.ensaio);
    expect(
      find.text('checagem externa: 3 ouvintes'),
      findsOneWidget,
      reason: 'a casa da gravação não contava os ouvintes, só a retrotradução',
    );
  });

  testWidgets('a finish the room never got is sent again by «Outro ouvinte», '
      'with the same answer, and nothing is shown of it', (tester) async {
    final harness = _aprovadaNaSala();
    harness.room.failTheNextFinishesWith.add(const NetworkFailed('sem rede'));
    final tablet = await _noAgradecimento(tester, harness);
    expect(find.text(_naoAbriu), findsNothing);
    _oAgradecimento();

    await _tocar(tester, _outroOuvinte);

    expect(harness.room.listenersFinished, [
      (version: 1, number: 1, completed: true),
      (version: 1, number: 1, completed: true),
    ]);
    expect(find.text('ouvinte 2'), findsOneWidget);
    await _fechar(tester, tablet);
  });

  testWidgets('a finish the room never got is sent again by «Terminar a '
      'checagem»', (tester) async {
    final harness = _aprovadaNaSala();
    harness.room.failTheNextFinishesWith.add(const NetworkFailed('sem rede'));
    final tablet = await _noAgradecimento(tester, harness);

    await _tocar(tester, _terminarAChecagem);

    expect(harness.room.listenersFinished, [
      (version: 1, number: 1, completed: true),
      (version: 1, number: 1, completed: true),
    ]);
    expect(_sala(tablet).stage, SalaStage.ensaio);
  });

  testWidgets('taps on the end screen while the finish is in the air send '
      'one finish and ask one number', (tester) async {
    final harness = _aprovadaNaSala();
    harness.room.holdNextFinish();
    final tablet = await _noAgradecimento(tester, harness);

    expect(_habilitado(tester, _outroOuvinte), isFalse);
    expect(_habilitado(tester, _terminarAChecagem), isFalse);
    await _tocar(tester, _outroOuvinte);
    await _tocar(tester, _outroOuvinte);
    await _tocar(tester, _terminarAChecagem);
    harness.room.finishHeldFinish();
    await _passar(tester);
    expect(_habilitado(tester, _outroOuvinte), isTrue);
    await _tocar(tester, _outroOuvinte);

    expect(harness.room.listenersFinished, [
      (version: 1, number: 1, completed: true),
    ]);
    expect(harness.room.listenersAsked, hasLength(2));
    expect(find.text('ouvinte 2'), findsOneWidget);
    await _fechar(tester, tablet);
  });

  testWidgets('a finish that fails twice does not hold the team', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    harness.room.failTheNextFinishesWith.addAll(const [
      NetworkFailed('sem rede'),
      NetworkFailed('sem rede'),
    ]);
    final tablet = await _noAgradecimento(tester, harness);

    await _tocar(tester, _outroOuvinte);

    expect(harness.room.listenersFinished, hasLength(2));
    expect(harness.room.finishedListeners, isEmpty);
    expect(find.text(_naoAbriu), findsNothing);
    expect(harness.room.listenersAsked, hasLength(2));
    expect(find.text('ouvinte 2'), findsOneWidget);
    await _fechar(tester, tablet);
  });

  testWidgets('a relaunch while the passage plays, before any retelling, comes '
      'back to the retelling with the circle open and nothing said', (
    tester,
  ) async {
    final first = await _aberta(tester, _aprovadaNaSala());
    await _tocar(tester, _checagem);
    await _tocar(tester, _novoOuvinte);

    final again = await _relancar(tester, first);
    await _tocar(tester, _checagem);

    expect(_sala(again).stage, SalaStage.checagem);
    expect(find.text('ouvinte 1'), findsOneWidget);
    expect(find.text(_contem), findsOneWidget);
    expect(_falasX(again.harness), isEmpty);
    expect(again.harness.playback.played, isEmpty);
    expect(again.harness.room.listenersAsked, hasLength(1));
    await _tocar(tester, _circulo);
    expect(_gravacoes(again.harness), 1);
  });

  testWidgets('a relaunch inside the check lands on the conversation, and '
      '«Checagem externa» from the home comes back to the same listener', (
    tester,
  ) async {
    final first = await _aberta(tester, _aprovadaNaSala());
    await _tocar(tester, _checagem);
    await _tocar(tester, _novoOuvinte);

    final again = await _relancar(tester, first, pelaBolinha: false);

    expect(
      _sala(again).stage,
      SalaStage.conversa,
      reason: 'a checagem reabria sozinha no relançamento, fora da conversa',
    );
    expect(byLabel('Ouvir de novo'), findsOneWidget);
    await tester.runAsync(() async {
      again.container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await _passar(tester);
    await _tocar(tester, _checagem);

    expect(_sala(again).stage, SalaStage.checagem);
    expect(find.text('ouvinte 1'), findsOneWidget);
    expect(again.harness.room.listenersRead, [1]);
    expect(again.harness.room.listenersAsked, hasLength(1));
  });

  testWidgets('a relaunch inside the check leaves it to the recording home', (
    tester,
  ) async {
    final first = await _aberta(tester, _aprovadaNaSala());
    await _tocar(tester, _checagem);
    await _tocar(tester, _novoOuvinte);

    final again = await _relancar(tester, first);
    await _tocar(tester, _checagem);
    await _tocar(tester, _voltar);

    expect(_sala(again).stage, SalaStage.ensaio);
    expect(
      first.harness.emAberto.rows['$_linha/pt']?.stage,
      equals(SalaStage.ensaio),
    );
  });

  testWidgets('a relaunch after the retelling landed and its finish was lost '
      'comes to the thanks, never asks the retelling again, and finishes the '
      'listener', (tester) async {
    final harness = _aprovadaNaSala();
    harness.room.failTheNextFinishesWith.add(const NetworkFailed('sem rede'));
    final first = await _noAgradecimento(tester, harness);

    final again = await _relancar(tester, first);
    await _tocar(tester, _checagem);

    _oAgradecimento();
    expect(_falasX(again.harness), isEmpty);
    expect(_gravacoes(again.harness), 0);
    expect(harness.room.listenersFinished.last, (
      version: 1,
      number: 1,
      completed: true,
    ));
    expect(harness.room.finishedListeners, {1: true});
  });

  testWidgets('a retelling the room stored whose answer was lost counts as '
      'stored on the relaunch', (tester) async {
    final harness = _aprovadaNaSala();
    final first = await _noReconto(tester, harness);
    harness.room.loseNextListenerRecordingAnswerWith = const NetworkFailed(
      'sem rede',
    );
    await _reconta(tester);
    expect(find.text(_contem), findsOneWidget);

    await _relancar(tester, first);
    await _tocar(tester, _checagem);

    _oAgradecimento();
    expect(harness.room.listenerRecordings, hasLength(1));
  });

  testWidgets('a listener the room has finished resumes on the thanks, nothing '
      'is sent again, and «Outro ouvinte» takes the next number', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final first = await _noAgradecimento(tester, harness);
    final finishes = harness.room.listenersFinished.length;

    final again = await _relancar(tester, first);
    await _tocar(tester, _checagem);

    _oAgradecimento();
    expect(harness.room.listenersRead, [1]);
    expect(_falasX(again.harness), isEmpty);
    expect(harness.room.listenersFinished, hasLength(finishes));
    await _tocar(tester, _outroOuvinte);
    expect(harness.room.listenersFinished, hasLength(finishes));
    expect(find.text('ouvinte 2'), findsOneWidget);
    await _fechar(tester, again);
  });

  testWidgets('leaving by the back control before any retelling forgets the '
      'listener: the next entry offers «Novo ouvinte» with the next number', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final tablet = await _aberta(tester, harness);
    await _tocar(tester, _checagem);
    await _tocar(tester, _novoOuvinte);
    await _tocar(tester, _voltar);

    await _tocar(tester, _checagem);

    expect(byLabel(_novoOuvinte), findsOneWidget);
    expect(harness.room.listenersRead, isEmpty);
    await _tocar(tester, _novoOuvinte);
    expect(find.text('ouvinte 2'), findsOneWidget);
    expect(harness.room.listenersFinished, isEmpty);
    await _fechar(tester, tablet);
  });

  testWidgets('the back control while the retelling is in the air keeps the '
      'listener once it lands: the next entry is their thanks', (tester) async {
    final harness = _aprovadaNaSala();
    await _noReconto(tester, harness);
    harness.room.holdNextListenerRecording();
    await _reconta(tester);
    await _tocar(tester, _voltar);

    harness.room.finishHeldListenerRecording();
    await _passar(tester);
    await _tocar(tester, _checagem);

    _oAgradecimento();
    expect(harness.room.listenersAsked, hasLength(1));
    expect(harness.room.listenersFinished, [
      (version: 1, number: 1, completed: true),
    ]);
  });

  testWidgets('the back control while the retelling is in the air lets the '
      'listener go once it fails: the next entry asks a new number', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final tablet = await _noReconto(tester, harness);
    harness.room
      ..holdNextListenerRecording()
      ..failNextListenerRecordingWith = const NetworkFailed('sem rede');
    await _reconta(tester);
    await _tocar(tester, _voltar);

    harness.room.finishHeldListenerRecording();
    await _passar(tester);
    await _tocar(tester, _checagem);

    expect(byLabel(_novoOuvinte), findsOneWidget);
    await _tocar(tester, _novoOuvinte);
    expect(find.text('ouvinte 2'), findsOneWidget);
    expect(harness.room.listenersFinished, isEmpty);
    await _fechar(tester, tablet);
  });

  testWidgets('a row left on the check whose draft was reopened elsewhere '
      'resumes on the recording home', (tester) async {
    final harness = _aprovadaNaSala(stage: SalaStage.checagem);
    harness.room.approvedDraft = null;
    final tablet = await _aberta(tester, harness);

    expect(_sala(tablet).stage, SalaStage.ensaio);
    await _fechar(tester, tablet);
  });

  testWidgets('a remembered listener of an older version is forgotten and the '
      'check opens at «Novo ouvinte»', (tester) async {
    final harness = _aprovadaNaSala(
      stage: SalaStage.checagem,
      ouvinte: (version: 1, number: 2),
    );
    harness.room.approvedDraft = const ApprovedDraft(version: 2);
    final tablet = await _aberta(tester, harness);
    expect(_sala(tablet).stage, SalaStage.ensaio);

    await _tocar(tester, _checagem);

    expect(byLabel(_novoOuvinte), findsOneWidget);
    expect(harness.room.listenersRead, isEmpty);
    await _tocar(tester, _novoOuvinte);
    expect(harness.room.listenersAsked.single.version, 2);
    await _fechar(tester, tablet);
  });

  testWidgets('a listener the room cannot read leaves the team on the '
      'recording home with her words, and the next tap tries again', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final first = await _noReconto(tester, harness);
    harness.room.failNextListenerReadWith = const NetworkFailed('sem rede');

    final again = await _relancar(tester, first);
    await _tocar(tester, _checagem);

    expect(_sala(again).stage, SalaStage.ensaio);
    expect(
      find.text(_naoAbriu),
      findsOneWidget,
      reason: 'a casa calava a checagem que não abriu',
    );
    expect(_sala(again).needsPerson, isFalse);
    await _tocar(tester, _checagem);
    expect(find.text('ouvinte 1'), findsOneWidget);
    expect(find.text(_contem), findsOneWidget);
  });

  testWidgets('a listener the room no longer knows sends the team to the '
      'Choice and the row is forgotten', (tester) async {
    final harness = _aprovadaNaSala(
      stage: SalaStage.checagem,
      ouvinte: (version: 1, number: 7),
    );

    final tablet = await _aberta(tester, harness);
    await _tocar(tester, _checagem);

    expect(_sala(tablet).stage, SalaStage.escolha);
    expect(harness.emAberto.rows['$_linha/pt']?.listener, isNull);
  });

  testWidgets('a session zeroed on the Desk sends the team to the Choice from '
      'the check opened again, and the row no longer names the listener', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final first = await _noReconto(tester, harness);
    harness.room.failNextListenerReadWith = const SessionGone();

    final again = await _relancar(tester, first);
    await _tocar(tester, _checagem);

    expect(_sala(again).stage, SalaStage.escolha);
    expect(harness.room.listenersRead, [1]);
    expect(harness.emAberto.rows['$_linha/pt'], isNull);
  });

  testWidgets('a resume onto the approved draft counts as a resume that '
      'landed, so two refusals around it do not forget the row', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final tablet = await _noReconto(tester, harness);
    const recusa = Refused('RECUSADA');

    harness.room.failStateOnceWith = recusa;
    await _entrarDeNovo(tester, tablet);
    await _entrarDeNovo(tester, tablet);
    expect(_sala(tablet).stage, SalaStage.conversa);
    harness.room.failStateOnceWith = recusa;
    await _entrarDeNovo(tester, tablet);

    expect(harness.emAberto.rows['$_linha/pt']?.listener, (
      version: 1,
      number: 1,
    ));
  });

  testWidgets('another tablet resumes nothing, and its «Novo ouvinte» takes '
      'the next number', (tester) async {
    final harness = _aprovadaNaSala();
    final first = await _noReconto(tester, harness);
    await tester.pumpWidget(const SizedBox());
    first.container.dispose();
    final outro = _umTablet(room: harness.room);
    _naLinha(outro);
    final segundo = await _aberta(tester, outro);

    await _tocar(tester, _checagem);

    expect(byLabel(_novoOuvinte), findsOneWidget);
    await _tocar(tester, _novoOuvinte);
    expect(find.text('ouvinte 2'), findsOneWidget);
    await _fechar(tester, segundo);
  });

  testWidgets('after «Terminar a checagem», a relaunch resumes no one', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    final first = await _noAgradecimento(tester, harness);
    await _tocar(tester, _terminarAChecagem);

    final again = await _relancar(tester, first);

    expect(_sala(again).stage, SalaStage.ensaio);
    await _tocar(tester, _checagem);
    expect(byLabel(_novoOuvinte), findsOneWidget);
    expect(harness.room.listenersRead, isEmpty);
  });

  testWidgets('a thanks that cannot sound leaves the thanks step standing', (
    tester,
  ) async {
    final harness = _aprovadaNaSala();
    harness.voice.refuses.add('X4');
    await _noReconto(tester, harness);

    await _reconta(tester);

    _oAgradecimento();
    expect(find.text(_ouvirDeNovo), findsNothing);
    expect(find.text(_naoAbriu), findsNothing);
    expect(harness.room.listenersFinished, [
      (version: 1, number: 1, completed: true),
    ]);
  });

  testWidgets('in English, her thanks and its words are English', (
    tester,
  ) async {
    final harness = _aprovadaNaSala(lingua: 'en');
    final tablet = await _aberta(tester, harness);
    await _tocar(tester, 'External check');
    await _tocar(tester, 'New listener');
    tablet.harness.playback.finishPlayback();
    await _passar(tester);
    await _tocar(tester, 'Tap to tell what you heard');
    await _tocar(tester, 'Tap to tell what you heard');

    expect(_falasX(harness).last, ('X4', 'en'));
    _oAgradecimento(
      agradecemos: 'Thank you for your help.',
      outro: 'Another listener',
      terminar: 'Finish the check',
    );
    harness.room.approvedDraft = const ApprovedDraft(version: 1, listeners: 3);
    await _tocar(tester, 'Finish the check');
    expect(find.text('external check: 3 listeners'), findsOneWidget);
  });

  test('a resume point written before the listener existed reads as no '
      'listener', () {
    const antiga =
        '{"session_id":"sessao-antiga","stage":"checagem","takes":[]}';

    final linha = ResumePoint.fromJson(
      jsonDecode(antiga) as Map<String, Object?>,
      folder: '/gravacoes',
    )!;

    expect(linha.listener, isNull);
  });

  test('the listener in progress survives the disk', () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso-ouvinte');
    addTearDown(() => home.deleteSync(recursive: true));
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => Directory('${home.path}/recordings'),
    );

    await ledger.remember(
      'Ruth',
      'P01',
      'pt',
      const ResumePoint(
        sessionId: _sessao,
        stage: SalaStage.checagem,
        listener: (version: 2, number: 3),
      ),
    );

    expect((await ledger.of('Ruth', 'P01', 'pt'))!.listener, (
      version: 2,
      number: 3,
    ));
  });
}
