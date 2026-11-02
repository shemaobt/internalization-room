import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaCasa;
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, isHeard, thePersonSign;

const _checagem = 'Checagem externa';
const _novoOuvinte = 'Novo ouvinte';
const _voltar = 'Voltar para a gravação';
const _badge = '✓ aprovado como rascunho final (v1)';
const _sinal = 'Um momento para uma pessoa';

const _ouvinte1 = 'ouvinte 1';
const _ouvindo = 'ouvindo a passagem inteira…';
const _contem = 'Contem, do jeito de vocês, o que ouviram.';
const _toque = 'toque no círculo para falar; toque de novo para parar';
const _gravando = 'gravando';
const _ouvirDeNovo = 'ouvir de novo';
const _circulo = 'Toque para contar o que ouviu';
const _naoAbriu = 'não deu para abrir a checagem externa — tentem de novo';
const _naoGuardou = 'não deu para guardar essa gravação — gravem de novo';

const _partes = ['t1', 't2', 't3'];

Uint8List _audioDe(String take) =>
    Uint8List.fromList(utf8.encode('a parte aprovada $take ' * 40));

final _reconto = Uint8List.fromList(List.generate(4000, (i) => i % 251));

SalaSessionState _sala(ProviderContainer container) =>
    container.read(salaSessionProvider);

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

bool? _habilitado(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

int _gravacoes(SalaHarness harness) =>
    harness.sounds.where((sound) => sound == 'recorder:start').length;

List<String> _ouvidoDesde(
  SalaHarness harness,
  int desde, [
  List<String> takes = const [..._partes, 't9'],
]) => [
  for (final path in harness.playback.played.skip(desde))
    for (final take in takes)
      if (File(path).existsSync() &&
          _iguais(File(path).readAsBytesSync(), _audioDe(take)))
        take,
];

bool _iguais(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i] == b[i]);

List<(String, String)> _falasX(SalaHarness harness) => [
  for (final line in harness.voice.fixedLines)
    if (line.$1.startsWith('X')) line,
];

Future<ProviderContainer> _naChecagem(
  WidgetTester tester,
  SalaHarness harness, {
  List<String> partes = _partes,
}) async {
  final container = await aprovadaNaCasa(tester, harness);
  harness.room.checkTakes = partes;
  for (final take in [..._partes, 't9']) {
    harness.room.takeAudio[take] = _audioDe(take);
  }
  harness.recorder.rehearsalSpeaks = _reconto;
  harness.recorder.rehearsalSpeaksAs = 'm4a';
  await _tocar(tester, _checagem);
  return container;
}

SalaSessionNotifier _notifier(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

Future<void> _umaParadaNaChecagem(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).haltForABrokenBuild();
  await _passar(tester);
  expect(
    _sala(container).needsPerson,
    isFalse,
    reason: 'a parada cobria a checagem, e o dela só fica sobre a conversa',
  );
  expect(thePersonSign, findsNothing);
}

Future<void> _terminarAsPartes(
  WidgetTester tester,
  SalaHarness harness, {
  int partes = 3,
}) async {
  for (var i = 0; i < partes; i++) {
    harness.playback.finishPlayback();
    await _passar(tester);
  }
}

Future<ProviderContainer> _noReconto(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _naChecagem(tester, harness);
  await _tocar(tester, _novoOuvinte);
  await _terminarAsPartes(tester, harness);
  expect(find.text(_toque), findsOneWidget);
  return container;
}

void main() {
  testWidgets('«Novo ouvinte» gives «ouvinte 1», says X-open, then plays the '
      'approved version\'s parts in order', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    final desde = harness.playback.played.length;
    harness.voice.holdNextLine();

    await _tocar(tester, _novoOuvinte);

    expect(harness.room.listenersAsked.map((a) => (a.sessionId, a.version)), [
      (_sala(container).sessionId, 1),
    ]);
    expect(find.text(_ouvinte1), findsOneWidget);
    expect(_falasX(harness), [('X0', 'pt')]);
    expect(harness.playback.played.length, desde);

    harness.voice.finishHeldLine();
    await _passar(tester);
    expect(find.text(_ouvindo), findsOneWidget);
    harness.playback.finishPlayback();
    await _passar(tester);
    harness.playback.finishPlayback();
    await _passar(tester);

    expect(_ouvidoDesde(harness, desde), _partes);
    expect(_falasX(harness), [('X0', 'pt')]);
    closeTheRoom(container);
  });

  testWidgets('the circle does nothing while X-open speaks and while the '
      'passage plays', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    final gravacoes = _gravacoes(harness);
    harness.voice.holdNextLine();
    await _tocar(tester, _novoOuvinte);
    expect(find.text(_ouvinte1), findsOneWidget);

    await _tocar(tester, _circulo);
    expect(_gravacoes(harness), gravacoes);

    harness.voice.finishHeldLine();
    await _passar(tester);
    for (var i = 0; i < _partes.length - 1; i++) {
      await _tocar(tester, _circulo);
      expect(_gravacoes(harness), gravacoes);
      harness.playback.finishPlayback();
      await _passar(tester);
    }
    await _tocar(tester, _circulo);

    expect(_gravacoes(harness), gravacoes);
    expect(harness.room.listenerRecordings, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('after the last part, X-retell, then the circle opens', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    await _tocar(tester, _novoOuvinte);
    harness.playback.finishPlayback();
    await _passar(tester);
    harness.playback.finishPlayback();
    await _passar(tester);
    harness.voice.holdNextLine();
    final gravacoes = _gravacoes(harness);

    harness.playback.finishPlayback();
    await _passar(tester);

    expect(_falasX(harness), [('X0', 'pt'), ('X1', 'pt')]);
    expect(find.text(_contem), findsOneWidget);
    await _tocar(tester, _circulo);
    expect(_gravacoes(harness), gravacoes);

    harness.voice.finishHeldLine();
    await _passar(tester);
    expect(find.text(_toque), findsOneWidget);
    await _tocar(tester, _circulo);
    expect(_gravacoes(harness), gravacoes + 1);
    closeTheRoom(container);
  });

  testWidgets('a retelling records with «gravando» and a clock, and lands as '
      'one retell under listener 1 the moment it stops', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);

    await tester.tap(byLabel(_circulo));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('$_gravando · 0:03'), findsOneWidget);
    expect(find.text(_toque), findsNothing);

    await _tocar(tester, _circulo);

    expect(harness.room.listenerRecordings, hasLength(1));
    final kept = harness.room.listenerRecordings.single;
    expect((kept.version, kept.listener, kept.kind), (1, 1, 'retell'));
    expect(kept.bytes, _reconto);
    expect(harness.recorder.deleted, contains(harness.recorder.lastPath));
    expect(find.textContaining(_gravando), findsNothing);
    expect(find.text('Agradecemos sua ajuda.'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('the parts play from the approved version, not from the parts '
      'the team holds now', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness, partes: ['t1', 't2']);
    final desde = harness.playback.played.length;
    final buscados = harness.room.clipsFetched.length;

    await _tocar(tester, _novoOuvinte);
    harness.playback.finishPlayback();
    await _passar(tester);

    expect(
      harness.room.clipsFetched
          .skip(buscados)
          .where((url) => url.contains('/takes/')),
      [endsWith('/takes/t1/audio'), endsWith('/takes/t2/audio')],
    );
    expect(_ouvidoDesde(harness, desde), ['t1', 't2']);
    closeTheRoom(container);
  });

  testWidgets('a part that fails stops the passage, and «ouvir de novo» plays '
      'it again from the start with no line', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    await _tocar(tester, _novoOuvinte);
    harness.playback.finishPlayback();
    await _passar(tester);

    harness.playback.failPlayback();
    await _passar(tester);

    expect(find.text(_ouvirDeNovo), findsOneWidget);
    expect(find.text(_contem), findsNothing);
    final falas = List.of(harness.voice.fixedLines);
    final desde = harness.playback.played.length;

    await _tocar(tester, _ouvirDeNovo);
    expect(harness.voice.fixedLines, falas);
    await _terminarAsPartes(tester, harness);

    expect(_ouvidoDesde(harness, desde), _partes);
    expect(_falasX(harness), [('X0', 'pt'), ('X1', 'pt')]);
    closeTheRoom(container);
  });

  testWidgets('a part the room cannot hand back stalls the passage the same '
      'way', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.room.refuseClipOf.add('t2');
    final desde = harness.playback.played.length;

    await _tocar(tester, _novoOuvinte);

    expect(harness.playback.played.length, desde);
    expect(find.text(_ouvirDeNovo), findsOneWidget);
    harness.room.refuseClipOf.clear();
    await _tocar(tester, _ouvirDeNovo);
    await _terminarAsPartes(tester, harness);

    expect(_ouvidoDesde(harness, desde), _partes);
    expect(_falasX(harness), [('X0', 'pt'), ('X1', 'pt')]);
    closeTheRoom(container);
  });

  testWidgets('there is no way to the retelling but the end of the passage', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    await _tocar(tester, _novoOuvinte);
    harness.playback.finishPlayback();
    await _passar(tester);

    expect(find.text(_ouvindo), findsOneWidget);
    expect(byLabel('continuar'), findsNothing);
    expect(find.text('continuar'), findsNothing);
    expect(find.text(_ouvirDeNovo), findsNothing);
    expect(find.text(_contem), findsNothing);
    expect(_falasX(harness), [('X0', 'pt')]);
    closeTheRoom(container);
  });

  testWidgets('at the retelling, «ouvir de novo» plays the passage with no '
      'line, and the circle stops it to record', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    final falas = List.of(harness.voice.fixedLines);
    final desde = harness.playback.played.length;

    await _tocar(tester, _ouvirDeNovo);
    expect(_ouvidoDesde(harness, desde), ['t1']);
    expect(harness.voice.fixedLines, falas);
    final antes = harness.sounds.length;

    await _tocar(tester, _circulo);

    final depois = harness.sounds.skip(antes).toList();
    expect(depois, contains('recorder:start'));
    expect(
      depois.indexOf('playback:stop'),
      inInclusiveRange(0, depois.indexOf('recorder:start')),
    );
    expect(harness.voice.fixedLines, falas);
    closeTheRoom(container);
  });

  testWidgets('a retelling under 800 bytes leaves nothing; one of 800 bytes '
      'goes up', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    harness.recorder.rehearsalSpeaks = Uint8List(799);

    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);

    expect(harness.room.listenerRecordings, isEmpty);
    expect(find.text(_naoGuardou), findsNothing);
    expect(find.text(_toque), findsOneWidget);

    harness.recorder.rehearsalSpeaks = Uint8List(800);
    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);

    expect(harness.room.listenerRecordings.map((r) => r.kind), ['retell']);
    closeTheRoom(container);
  });

  testWidgets('a retelling that does not reach the room shows her words and '
      'the circle opens again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    harness.room.failNextListenerRecordingWith = const NetworkFailed(
      'sem rede',
    );

    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);

    expect(find.text(_naoGuardou), findsOneWidget);
    expect(thePersonSign, findsNothing);
    expect(find.text(_sinal), findsNothing);
    expect(harness.recorder.deleted, contains(harness.recorder.lastPath));
    expect(harness.room.listenerRecordings, isEmpty);

    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);

    expect(harness.room.listenerRecordings.map((r) => r.kind), ['retell']);
    expect(find.text(_naoGuardou), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('while a retelling is sent, the circle and «ouvir de novo» do '
      'nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    harness.room.holdNextListenerRecording();
    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);
    final gravacoes = _gravacoes(harness);
    final desde = harness.playback.played.length;

    await _tocar(tester, _circulo);
    await _tocar(tester, _ouvirDeNovo);

    expect(_gravacoes(harness), gravacoes);
    expect(harness.playback.played.length, desde);
    expect(_habilitado(tester, _ouvirDeNovo), isFalse);
    harness.room.finishHeldListenerRecording();
    await _passar(tester);
    closeTheRoom(container);
  });

  testWidgets('a number the room cannot give shows her words and «Novo '
      'ouvinte» stays', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.room.failNextListenerWith = const NetworkFailed('sem rede');
    final falas = List.of(harness.voice.fixedLines);

    await _tocar(tester, _novoOuvinte);

    expect(find.text(_naoAbriu), findsOneWidget);
    expect(thePersonSign, findsNothing);
    expect(harness.voice.fixedLines, falas);
    expect(_habilitado(tester, _novoOuvinte), isTrue);

    await _tocar(tester, _novoOuvinte);

    expect(find.text(_ouvinte1), findsOneWidget);
    expect(find.text(_naoAbriu), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('«Novo ouvinte» tapped again after a lost answer sends the same '
      'attempt', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.room.failNextListenerWith = const NetworkFailed('sem rede');

    await _tocar(tester, _novoOuvinte);
    await _tocar(tester, _novoOuvinte);

    final attempts = harness.room.listenersAsked.map((a) => a.attempt);
    expect(attempts, hasLength(2));
    expect(attempts.toSet(), hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('a session zeroed on the Desk before «Novo ouvinte» sends the '
      'team to the Choice', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.room.forgetTheSession(_sala(container).sessionId!);

    await _tocar(tester, _novoOuvinte);

    expect(harness.room.askedOfTheForgotten, contains('aNewListener'));
    expect(_sala(container).stage, SalaStage.escolha);
    closeTheRoom(container);
  });

  testWidgets('a session zeroed on the Desk before the retelling is sent '
      'sends the team to the Choice', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    await _tocar(tester, _circulo);
    harness.room.forgetTheSession(_sala(container).sessionId!);

    await _tocar(tester, _circulo);

    expect(
      harness.room.askedOfTheForgotten,
      contains('sendTheListenerRecording'),
    );
    expect(_sala(container).stage, SalaStage.escolha);
    closeTheRoom(container);
  });

  testWidgets('leaving while the listener speaks discards the half-recording '
      'and sends nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    await _tocar(tester, _circulo);
    final antes = harness.sounds.length;

    await _tocar(tester, _voltar);

    expect(harness.sounds.skip(antes), contains('recorder:discard'));
    expect(harness.room.listenerRecordings, isEmpty);
    expect(find.text(_badge), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a refused microphone at the retelling changes nothing the '
      'listener sees', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    harness.recorder.permitted = false;

    await _tocar(tester, _circulo);

    expect(thePersonSign, findsNothing);
    expect(find.text(_naoGuardou), findsNothing);
    expect(find.text(_toque), findsOneWidget);

    harness.recorder.permitted = true;
    harness.recorder.startThrows = true;
    await _tocar(tester, _circulo);

    expect(thePersonSign, findsNothing);
    expect(find.text(_naoGuardou), findsNothing);
    expect(find.text(_toque), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('in an English session, the X lines and the words are English', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aprovadaNaCasa(
      tester,
      harness,
      caminho: (
        terminei: 'done',
        aprovar: 'Approve as the final draft',
        salvo: 'Rehearsal saved',
        pronto: 'Done',
      ),
    );
    harness.room.checkTakes = _partes;
    for (final take in _partes) {
      harness.room.takeAudio[take] = _audioDe(take);
    }
    harness.recorder.rehearsalSpeaks = _reconto;
    harness.recorder.rehearsalSpeaksAs = 'm4a';
    await _tocar(tester, 'External check');

    await _tocar(tester, 'New listener');
    expect(find.text('listener 1'), findsOneWidget);
    expect(find.text('listening to the whole passage…'), findsOneWidget);
    await _terminarAsPartes(tester, harness);

    expect(_falasX(harness), [('X0', 'en'), ('X1', 'en')]);
    expect(find.text('Tell, in your own way, what you heard.'), findsOneWidget);
    expect(
      find.text('tap the circle to speak; tap again to stop'),
      findsOneWidget,
    );
    expect(byLabel('hear it again'), findsOneWidget);
    await tester.tap(byLabel('Tap to tell what you heard'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('recording · 0:01'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('an X-open that cannot sound does not stop the listener', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.voice.refuses.add('X0');
    final desde = harness.playback.played.length;
    final gravacoes = _gravacoes(harness);

    await _tocar(tester, _novoOuvinte);
    await _terminarAsPartes(tester, harness);

    expect(_ouvidoDesde(harness, desde), _partes);
    expect(find.text(_toque), findsOneWidget);
    await _tocar(tester, _circulo);
    expect(_gravacoes(harness), gravacoes + 1);
    closeTheRoom(container);
  });

  testWidgets('an X-open the room cannot hand over does not stop the '
      'listener', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.voice.roomFailsFor['X0'] = const NetworkFailed('sem rede');
    final desde = harness.playback.played.length;

    await _tocar(tester, _novoOuvinte);
    await _terminarAsPartes(tester, harness);

    expect(_ouvidoDesde(harness, desde), _partes);
    expect(find.text(_toque), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('the station never plays the listener\'s own recording back', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);
    expect(harness.room.listenerRecordings, hasLength(1));
    final desde = harness.playback.played.length;

    await _tocar(tester, 'Outro ouvinte');

    expect(_ouvidoDesde(harness, desde), ['t1']);
    expect(
      harness.playback.played.where(
        (path) =>
            File(path).existsSync() &&
            _iguais(File(path).readAsBytesSync(), _reconto),
      ),
      isEmpty,
    );
    final controles = {
      for (final control
          in find
              .byElementPredicate(
                (element) =>
                    element.widget is Semantics &&
                    ((element.widget as Semantics).properties.button ??
                        false) &&
                    isHeard(element),
              )
              .evaluate()
              .map((element) => element.widget as Semantics))
        control.properties.label,
    };
    expect(controles, {_voltar, _circulo});
    closeTheRoom(container);
  });

  testWidgets('«Novo ouvinte» after a lost answer, a way back and a way in '
      'again sends the same attempt', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.room.failNextListenerWith = const NetworkFailed('sem rede');
    await _tocar(tester, _novoOuvinte);

    await _tocar(tester, _voltar);
    await _tocar(tester, _checagem);
    await _tocar(tester, _novoOuvinte);

    final attempts = harness.room.listenersAsked.map((a) => a.attempt);
    expect(attempts, hasLength(2));
    expect(attempts.toSet(), hasLength(1));
    expect(find.text(_ouvinte1), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('«Novo ouvinte» left while its answer is on the way, then tapped '
      'again, sends the same attempt', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    harness.room.holdNextListener();
    await _tocar(tester, _novoOuvinte);

    await _tocar(tester, _voltar);
    harness.room.finishHeldListener();
    await _passar(tester);
    await _tocar(tester, _checagem);
    await _tocar(tester, _novoOuvinte);

    final attempts = harness.room.listenersAsked.map((a) => a.attempt);
    expect(attempts, hasLength(2));
    expect(attempts.toSet(), hasLength(1));
    expect(find.text(_ouvinte1), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a halt while the passage plays on the check cuts nothing, and '
      'the passage plays on to X-retell, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    final desde = harness.playback.played.length;
    await _tocar(tester, _novoOuvinte);
    harness.playback.finishPlayback();
    await _passar(tester);

    await _umaParadaNaChecagem(tester, container);

    await _terminarAsPartes(tester, harness, partes: 2);
    expect(
      _ouvidoDesde(harness, desde),
      _partes,
      reason: 'a parada cortava a passagem no meio para o ouvinte',
    );
    expect(_falasX(harness).last, ('X1', 'pt'));
    closeTheRoom(container);
  });

  testWidgets('a halt during X-open on the check cuts nothing: X-open is said '
      'once, then the passage, X-retell and the circle, as hers', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    final desde = harness.playback.played.length;
    final gravacoes = _gravacoes(harness);
    harness.voice.holdNextLine();
    await _tocar(tester, _novoOuvinte);

    await _umaParadaNaChecagem(tester, container);

    harness.voice.finishHeldLine();
    await _passar(tester);
    await _terminarAsPartes(tester, harness);

    expect(
      _falasX(harness),
      [('X0', 'pt'), ('X1', 'pt')],
      reason: 'a parada cortava o X-open, que era dito de novo depois do toque',
    );
    expect(_ouvidoDesde(harness, desde), _partes);
    await _tocar(tester, _circulo);
    expect(_gravacoes(harness), gravacoes + 1);
    closeTheRoom(container);
  });

  testWidgets('a person called while «Novo ouvinte» is answered hears X-open '
      'once, then the passage once', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    final desde = harness.playback.played.length;
    harness.room.holdNextListener();
    await _tocar(tester, _novoOuvinte);

    _notifier(container).haltForABrokenBuild();
    await _passar(tester);
    harness.room.finishHeldListener();
    await _passar(tester);
    _notifier(container).teamTapped();
    await _passar(tester);
    await _passar(tester);
    await _terminarAsPartes(tester, harness);

    expect(_falasX(harness), [('X0', 'pt'), ('X1', 'pt')]);
    expect(_ouvidoDesde(harness, desde), _partes);
    closeTheRoom(container);
  });

  testWidgets('a second tap while the microphone is still opening does not '
      'close it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    harness.recorder.holdNextStart();
    await tester.tap(byLabel(_circulo));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(byLabel(_circulo));
    await tester.pump(const Duration(milliseconds: 100));
    harness.recorder.finishStart();
    await _passar(tester);

    expect(find.textContaining(_gravando), findsOneWidget);
    expect(harness.room.listenerRecordings, isEmpty);
    await _tocar(tester, _circulo);
    expect(harness.room.listenerRecordings, hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('a second tap while the retelling closes sends it once', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _noReconto(tester, harness);
    await _tocar(tester, _circulo);
    harness.recorder.holdNextStop();
    await tester.tap(byLabel(_circulo));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(byLabel(_circulo));
    await tester.pump(const Duration(milliseconds: 100));
    harness.recorder.finishStop();
    await _passar(tester);
    await _passar(tester);

    expect(harness.room.listenerRecordings, hasLength(1));
    expect(find.text('Agradecemos sua ajuda.'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a halt after X-open and before the first part on the check '
      'cuts nothing, and the passage plays, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    final desde = harness.playback.played.length;
    harness.room.holdNextClip();
    await _tocar(tester, _novoOuvinte);

    await _umaParadaNaChecagem(tester, container);
    harness.room.finishHeldClip();
    await _passar(tester);
    await _terminarAsPartes(tester, harness);

    expect(
      _ouvidoDesde(harness, desde),
      _partes,
      reason: 'a parada segurava a passagem até um toque no sinal',
    );
    closeTheRoom(container);
  });

  testWidgets('a halt during X-retell on the check cuts nothing: X-retell is '
      'said once, and then the circle opens, as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naChecagem(tester, harness);
    await _tocar(tester, _novoOuvinte);
    harness.playback.finishPlayback();
    await _passar(tester);
    harness.playback.finishPlayback();
    await _passar(tester);
    harness.voice.holdNextLine();
    harness.playback.finishPlayback();
    await _passar(tester);
    final gravacoes = _gravacoes(harness);

    await _umaParadaNaChecagem(tester, container);

    expect(
      _falasX(harness),
      [('X0', 'pt'), ('X1', 'pt')],
      reason:
          'a parada cortava o X-retell, que era dito de novo depois do toque',
    );
    harness.voice.finishHeldLine();
    await _passar(tester);
    expect(find.text(_toque), findsOneWidget);
    await _tocar(tester, _circulo);
    expect(_gravacoes(harness), gravacoes + 1);
    closeTheRoom(container);
  });
}
