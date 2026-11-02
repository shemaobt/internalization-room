import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/person_sign.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'fakes.dart';

/// Finds a widget by the label its `Semantics` node carries — the room's own
/// tests read the screen the way a screen reader would, not by widget type.
Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

bool isHeard(Element element) {
  var heard = true;
  element.visitAncestorElements((ancestor) {
    final above = ancestor.widget;
    if (above is ExcludeSemantics && above.excluding) heard = false;
    return heard;
  });
  return heard;
}

Finder offered(String label) => find.byElementPredicate(
  (element) =>
      element.widget is Semantics &&
      (element.widget as Semantics).properties.label == label &&
      isHeard(element),
);

void voiceOverTap(WidgetTester tester, String label) =>
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: tester.getSemantics(byLabel(label)).id,
      ),
    );

void voiceOverFocusLeaves(WidgetTester tester, Finder control) =>
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.didLoseAccessibilityFocus,
        viewId: tester.view.viewId,
        nodeId: tester.getSemantics(control).id,
      ),
    );

List<String> labelsHeard(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

Finder get thePersonSign => find.descendant(
  of: find.descendant(
    of: find.byType(PersonSign),
    matching: find.byWidgetPredicate(
      (widget) => widget is IgnorePointer && !widget.ignoring,
    ),
  ),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is FadeTransition && widget.opacity.status.isForwardOrCompleted,
  ),
);

Future<void> withRealLetters() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(
      File(
        '$fonts/Roboto-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await roboto.load();
}

void onAScreen(WidgetTester tester, Size screen, {required double bar}) {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar)
    ..viewPadding = FakeViewPadding(top: bar);
  addTearDown(tester.view.reset);
}

Finder onTheCircle(String label) => find.descendant(
  of: find.byType(FacilitatorCircle),
  matching: byLabel(label),
);

Finder inTheHome(String label) =>
    find.descendant(of: find.byType(EnsaioView), matching: byLabel(label));

bool _isASceneRow(Widget widget) =>
    widget.runtimeType.toString() == '_SceneRowView';

Finder onTheRows(String label) => find.descendant(
  of: find.byWidgetPredicate(_isASceneRow),
  matching: byLabel(label),
);

Finder offTheRows(String label) => find.byElementPredicate((element) {
  final widget = element.widget;
  if (widget is! Semantics || widget.properties.label != label) return false;
  var inside = false;
  element.visitAncestorElements((above) {
    inside = _isASceneRow(above.widget);
    return !inside;
  });
  return !inside;
});

Future<void> pressTheApproval(WidgetTester tester, String label) async {
  final approve = byLabel(label);
  await tester.ensureVisible(approve);
  final missWas = WidgetController.hitTestWarningShouldBeFatal;
  WidgetController.hitTestWarningShouldBeFatal = true;
  try {
    await tester.tap(approve);
  } finally {
    WidgetController.hitTestWarningShouldBeFatal = missWas;
  }
}

/// How many times the room has been asked to read the session's state back —
/// the only witness that a watch actually re-polled, since the watch itself
/// has no other observable trace.
int stateReads(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

Future<void> theChoiceOffersAPassage(ProviderContainer container) => waitFor(
  'a Escolha oferecer as entradas',
  () => container.read(salaSessionProvider).entriesOpen,
);

/// A fixed pause, for the gestures whose landing has no state of its own to wait on.
Future<void> settle([
  Duration delay = const Duration(milliseconds: 120),
]) async {
  await Future<void>.delayed(delay);
}

void traduzirOApontadoDeNovo(ProviderContainer container) {
  final estado = container.read(salaSessionProvider);
  container
      .read(salaSessionProvider.notifier)
      .traduzirAFraseDeNovo(estado.btTrechos.indexOf(estado.btFindingTrecho!));
}

const umaParteInteira = Duration(seconds: 30);

/// Record a part through the widget tree: two taps to bracket the take, a pump for the
/// binding to settle, then keep it and let it reach the room.
Future<void> gravarUmaParte(
  WidgetTester tester,
  ProviderContainer container,
  int cena,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.gravarACena(cena);
  notifier.gravarACena(cena);
  await waitFor(
    'a gravação da parte chegar',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    limit: const Duration(seconds: 2),
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  notifier.takeKeep();
  await theRoomNamesTheParts(
    tester,
    container,
    parts: container.read(salaSessionProvider).partes.length,
  );
}

/// Tell the part in the air back whole, from its beginning to its end, then let it finish.
Future<void> traduzirAParteInteira(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.playback.at = umaParteInteira;
  notifier.retroTap();
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
}

List<String> faixas(WidgetTester tester) => [
  for (final faixa in tester.widgetList<SceneStrip>(
    find.descendant(
      of: find.byType(RetroView),
      matching: find.byType(SceneStrip),
    ),
  ))
    [
      '${faixa.frases.length} contadas',
      if (faixa.stale.isNotEmpty) '${faixa.stale.length} regravadas',
      if (faixa.pausa != null) 'pausa',
    ].join(' · '),
];

class _FileThatAnswersAtOnce implements File {
  _FileThatAnswersAtOnce(String path) : _real = Zone.root.run(() => File(path));

  final File _real;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => Future.value(_real.existsSync());

  @override
  bool existsSync() => _real.existsSync();

  @override
  int lengthSync() => _real.lengthSync();

  @override
  Uint8List readAsBytesSync() => _real.readAsBytesSync();

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _real.writeAsStringSync(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _real.writeAsBytesSync(bytes, mode: mode, flush: flush);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

T withDiskThatAnswersAtOnce<T>(T Function() body) => IOOverrides.runZoned(
  body,
  createFile: (path) => _FileThatAnswersAtOnce(path),
);

const everyAcknowledgementLineTheAppEverHad = ['F0', 'F1', 'F2', 'F3'];

Future<void> theHaltIsLifted(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  harness.voice.roomFailsWith = null;
  notifier.teamTapped();
  await waitFor('a sala soltar', () => !read().needsPerson);
  await settle();
}

/// Kill the tablet and launch it again: a new container over the same disk and the same
/// room, opened only after the old one is gone.
Future<(SalaHarness, ProviderContainer)> relaunch(
  SalaHarness harness,
  ProviderContainer container, {
  String? lingua,
  Duration? linkPoll,
  Duration? busyCeiling,
  Duration? lookAgain,
  bool filaEmMemoria = false,
  WidgetTester? tester,
}) async {
  container.dispose();
  final bool frozen;
  if (tester == null) {
    final stillWriting = Completer<bool>();
    final giveUp = Timer(
      const Duration(seconds: 30),
      () => stillWriting.complete(true),
    );
    frozen = await Future.any([
      harness.takes.writingEnds().then((_) => false),
      stillWriting.future,
    ]);
    giveUp.cancel();
  } else {
    var stopped = false;
    unawaited(harness.takes.writingEnds().then((_) => stopped = true));
    final waited = Stopwatch()..start();
    while (!stopped && waited.elapsed < const Duration(seconds: 30)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    frozen = !stopped;
  }
  expect(
    frozen,
    isFalse,
    reason:
        'a vida antiga ainda escrevia a fila 30 s depois: uma escrita '
        'começada no relógio falso do teste não anda dentro de runAsync',
  );
  harness.endTheLifeOnTheDisk();
  final again = SalaHarness(
    filaEmMemoria: filaEmMemoria,
    room: harness.room,
    emAbertoNoDisco: harness.emAbertoNoDisco ?? harness.emAberto,
    takesHome: harness.takesHome,
    currentSession: harness.currentSession,
    roomLanguage: lingua == null ? harness.roomLanguage : null,
    look: harness.look,
    lingua: lingua ?? harness.lingua,
    linkPoll: linkPoll ?? harness.linkPoll,
    busyCeiling: busyCeiling ?? harness.busyCeiling,
    lookAgain: lookAgain ?? harness.lookAgain,
  );
  final next = again.container();
  addTearDown(next.dispose);
  return (again, next);
}

/// Open the Choice and tap the Panorama's entry, as the team does.
Future<void> enterThePanorama(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read, {
  Future<void> Function()? step,
}) => _enterTheEntry(notifier, read, (entry) => entry.isPanorama, step: step);

/// Open the Choice and tap [pericope]'s entry, as the team does.
Future<void> enterThePassage(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  String pericope,
) => _enterTheEntry(notifier, read, (entry) => entry.pericope == pericope);

Future<void> _enterTheEntry(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  bool Function(Passagem entry) isIt, {
  Future<void> Function()? step,
}) async {
  await notifier.abrirEscolha();
  await waitFor(
    'a Escolha abrir as entradas',
    () => read().entriesOpen,
    step: step,
  );
  final entry = read().naRoda!.where(isIt);
  expect(entry, isNotEmpty, reason: 'a roda não tem essa entrada');
  notifier.openTheEntry(entry.first);
}

/// The tablet holds [row]'s session for [book] [pericope]: the next launch reopens it on its
/// conversation.
Future<void> holdTheSession(
  SalaHarness harness,
  ResumePoint row, {
  String book = 'Ruth',
  String pericope = 'P01',
  String language = testLanguage,
}) async {
  harness.emAberto.rows['$book/$pericope/$language'] = row;
  await harness.currentSession.hold(
    CurrentSession(
      sessionId: row.sessionId,
      book: book,
      pericope: pericope,
      language: language,
    ),
  );
}

/// From the conversation the launch landed on to the recording home, with every part here.
Future<void> intoTheRecordingHome(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read, {
  Future<void> Function()? step,
}) async {
  await waitFor(
    'a sala pousar na conversa',
    () => read().station is Canvas && !read().awaitingTheGuide,
    step: step,
  );
  notifier.goEnsaio();
  await waitFor(
    'as partes chegarem à casa',
    () => read().station is Ensaio,
    step: step,
  );
}

/// From the conversation the launch landed on, through the orange dot, to the recording
/// home with the room's parts laid in.
Future<void> throughTheOrangeDot(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read, {
  Future<void> Function()? step,
}) async {
  await waitFor(
    'a sala pousar na conversa',
    () => read().station is Canvas && !read().awaitingTheGuide,
    step: step,
  );
  notifier.openTheEnsaioFinal();
  await waitFor(
    'as partes da sala chegarem à casa',
    () => read().station is Ensaio && read().partes.isNotEmpty,
    step: step,
  );
}

/// From the conversation the launch landed on, through the recording home, into the
/// telling-back.
Future<void> intoTheBackTranslation(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read, {
  Future<void> Function()? step,
}) async {
  await intoTheRecordingHome(notifier, read, step: step);
  notifier.startRetro();
  await waitFor('a tradução abrir', () => read().station is Retro, step: step);
}

Finder linhaDoEnsaio(int cena) => find.descendant(
  of: find.byType(EnsaioView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label == 'Cena $cena' ||
            (widget.properties.label ?? '').startsWith('Cena $cena,')),
  ),
);

/// Each Scene row's control under [controle], lit or not; a row without it reads null.
List<bool?> naLinhaDoEnsaio(WidgetTester tester, String controle) => [
  for (var cena = 1; linhaDoEnsaio(cena).evaluate().isNotEmpty; cena++)
    switch (find
        .descendant(of: linhaDoEnsaio(cena), matching: byLabel(controle))
        .evaluate()) {
      final achados when achados.isEmpty => null,
      final achados =>
        (achados.single.widget as Semantics).properties.enabled == true,
    },
];
