import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, onTheCircle;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        entrarNaTraducao,
        fimDaGravacao,
        parte,
        passaDoCursor,
        pausado,
        tocar,
        tocarNoCirculo;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

const _tell = 'Toque para traduzir esta frase';
const _playPause = 'Tocar ou pausar a gravação';
const _respeak = 'gravem a frase inteira';
const _tellEn = 'Tap to translate this sentence';
const _playPauseEn = 'Play or pause your recording';
const _respeakEn = 'record the whole sentence';
const _linhaNaoEntendi = 'não entendi — traduzam de novo esse pedaço';
const _vazia = Refused(RefusalCode.wordlessTelling);

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Finder _playButton() =>
    find.descendant(of: find.byType(RetroView), matching: byLabel(_playPause));

Finder _playButtonEn() => find.descendant(
  of: find.byType(RetroView),
  matching: byLabel(_playPauseEn),
);

Future<void> _tocarOuPausar(WidgetTester tester, [Finder? botao]) async {
  await tester.tap(botao ?? _playButton());
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pausarNoToque(WidgetTester tester, SalaHarness harness) async {
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
}

Future<void> _umaFraseContada(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await _pausarNoToque(tester, harness);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await waitFor(
    'a frase pousar',
    () => container.read(salaSessionProvider).btTrechos.isNotEmpty,
    step: () => _passo(tester),
  );
}

Future<void> _regravarAte(
  WidgetTester tester,
  SalaHarness harness,
  int n,
  String language,
) async {
  await tocar(tester, sceneRehearsalLabelFor('rerecordFrase', language, n: n));
  await _passo(tester);
}

PassoDaRegravacao? _passoDaRegravacao(ProviderContainer container) =>
    container.read(salaSessionProvider).btRegravacao?.passo;

Finder _naLinha(String texto) =>
    find.descendant(of: find.byType(FraseList), matching: find.text(texto));

void main() {
  group('the circle on the check', () {
    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» while a part plays', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);
      harness.playback.at = cabeca;
      await tester.pump(passaDoCursor);

      expect(container.read(salaSessionProvider).btClipRodando, isTrue);
      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» while the part is held with no pause standing', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = const Duration(seconds: 2);
      await tester.pump(passaDoCursor);

      await _tocarOuPausar(tester);

      expect(container.read(salaSessionProvider).btClipPausada, isTrue);
      expect(container.read(salaSessionProvider).btCortado, isFalse);
      expect(find.textContaining(pausado), findsOneWidget);
      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» while a pause stands', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);

      await _pausarNoToque(tester, harness);

      expect(container.read(salaSessionProvider).thePauseStands, isTrue);
      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» at the end of the recording', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).btClipEnded, isTrue);
      expect(find.text(fimDaGravacao), findsOneWidget);
      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» while the team records a stretch\'s translation', (
      tester,
    ) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);
      await _pausarNoToque(tester, harness);

      await tocarNoCirculo(tester);

      expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» while the room weighs the telling just sent', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);
      await _pausarNoToque(tester, harness);
      await tocarNoCirculo(tester);
      harness.room.holdNextChunk();

      await tocarNoCirculo(tester);

      expect(container.read(salaSessionProvider).btPhase, BtPhase.thinking);
      expect(onTheCircle(_tell), findsOneWidget);

      harness.room.finishHeldChunk();
      await tester.pump(const Duration(milliseconds: 300));
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» while a translation waits to be recorded again', (
      tester,
    ) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);
      await _umaFraseContada(tester, harness, container);

      await tocar(tester, sceneRehearsalLabelFor('retellFrase', 'pt', n: 1));

      expect(container.read(salaSessionProvider).btTraducaoPendente, isNotNull);
      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» when a stretch was heard without words, and the «não entendi» '
        'mark beside it keeps its own label', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      await _pausarNoToque(tester, harness);
      await tocarNoCirculo(tester);
      harness.room.failChunkWith = _vazia;

      await tocarNoCirculo(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).wordlessTelling, isTrue);
      expect(onTheCircle(_tell), findsOneWidget);
      expect(onTheCircle(_linhaNaoEntendi), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('on the check the circle is named «Toque para traduzir esta '
        'frase» after a clean verdict', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      await _umaFraseContada(tester, harness, container);
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.verdictChecked = true;

      unawaited(
        container.read(salaSessionProvider.notifier).finishBackTranslation(),
      );
      await waitFor(
        'o veredito chegar',
        () =>
            container.read(salaSessionProvider).btPhase == BtPhase.conferida &&
            container.read(salaSessionProvider).btVeredito,
        step: () => _passo(tester),
      );

      expect(onTheCircle(_tell), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('while a sentence is recorded again the circle is named '
        '«gravem a frase inteira» on every step, hearing, ready, recording, '
        'review and sending, as hers', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await quatroFrasesEmWav(tester, harness);

      await _regravarAte(tester, harness, 3, 'pt');
      expect(_passoDaRegravacao(container), PassoDaRegravacao.ouvindo);
      expect(onTheCircle(_respeak), findsOneWidget, reason: 'ouvindo');

      harness.playback.finishPlayback();
      await _passo(tester);
      await _passo(tester);
      expect(_passoDaRegravacao(container), PassoDaRegravacao.pronta);
      expect(onTheCircle(_respeak), findsOneWidget, reason: 'pronta');

      await tocarNoCirculo(tester);
      expect(_passoDaRegravacao(container), PassoDaRegravacao.gravando);
      expect(onTheCircle(_respeak), findsOneWidget, reason: 'gravando');

      harness.recorder.rehearsalSpeaks = aSpokenWav(
        length: const Duration(seconds: 2),
      );
      await tocarNoCirculo(tester);
      await _passo(tester);
      expect(_passoDaRegravacao(container), PassoDaRegravacao.revendo);
      expect(onTheCircle(_respeak), findsOneWidget, reason: 'revendo');

      final segura = harness.room.holdTheSentence = Completer<void>();
      await tester.tap(_naLinha('usar esta'));
      await _passo(tester);
      expect(_passoDaRegravacao(container), PassoDaRegravacao.enviando);
      expect(onTheCircle(_respeak), findsOneWidget, reason: 'enviando');

      segura.complete();
      await _passo(tester);
      closeTheRoom(container);
    });

    testWidgets('once the sentence recorded again is kept, the circle is '
        'named «Toque para traduzir esta frase» again', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await quatroFrasesEmWav(tester, harness);
      await _regravarAte(tester, harness, 3, 'pt');
      harness.playback.finishPlayback();
      await _passo(tester);
      await _passo(tester);
      await tocarNoCirculo(tester);
      harness.recorder.rehearsalSpeaks = aSpokenWav(
        length: const Duration(seconds: 2),
      );
      await tocarNoCirculo(tester);
      await _passo(tester);

      await tester.tap(_naLinha('usar esta'));
      await waitFor(
        'a frase ser guardada',
        () => container.read(salaSessionProvider).btRegravacao == null,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(onTheCircle(_tell), findsOneWidget);
      expect(onTheCircle(_respeak), findsNothing);
      closeTheRoom(container);
    });

    testWidgets('an english room names the circle «Tap to translate this '
        'sentence», and «record the whole sentence» while a sentence is '
        'recorded again', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
      final container = await quatroFrasesEmWav(tester, harness);
      expect(onTheCircle(_tellEn), findsOneWidget);

      await _regravarAte(tester, harness, 3, 'en');

      expect(onTheCircle(_respeakEn), findsOneWidget);
      expect(onTheCircle(_tellEn), findsNothing);
      closeTheRoom(container);
    });
  });

  group('the play button on the check', () {
    testWidgets('on the check the play button is named «Tocar ou pausar a '
        'gravação» before anything plays, while a part plays, and while a '
        'translation waits to be heard', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);
      expect(_playButton(), findsOneWidget, reason: 'antes de tocar');

      harness.playback.at = cabeca;
      await tester.pump(passaDoCursor);
      expect(container.read(salaSessionProvider).btClipRodando, isTrue);
      expect(_playButton(), findsOneWidget, reason: 'tocando');

      await _umaFraseContada(tester, harness, container);
      await tocar(tester, sceneRehearsalLabelFor('retellFrase', 'pt', n: 1));
      expect(container.read(salaSessionProvider).btTraducaoPendente, isNotNull);
      expect(_playButton(), findsOneWidget, reason: 'tradução à espera');
      closeTheRoom(container);
    });

    testWidgets('after a clean verdict the play button is named «Tocar ou '
        'pausar a gravação», playing or not', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      await _umaFraseContada(tester, harness, container);
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.verdictChecked = true;
      unawaited(
        container.read(salaSessionProvider.notifier).finishBackTranslation(),
      );
      await waitFor(
        'o veredito chegar',
        () =>
            container.read(salaSessionProvider).btPhase == BtPhase.conferida &&
            container.read(salaSessionProvider).btVeredito,
        step: () => _passo(tester),
      );
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_playButton(), findsOneWidget, reason: 'parado');

      await _tocarOuPausar(tester);

      expect(harness.playback.sounding, isTrue);
      expect(_playButton(), findsOneWidget, reason: 'tocando');
      closeTheRoom(container);
    });

    testWidgets('on the First listen the play button is named «Tocar ou '
        'pausar a gravação»', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.listeningUnheardTakeIds = const ['uma-parte-nao-ouvida'];
      final container = await entrarNaTraducao(tester, harness);
      await waitFor(
        'a primeira escuta abrir',
        () => container.read(salaSessionProvider).btSoOuvir,
        step: () => _passo(tester),
      );

      expect(_playButton(), findsOneWidget);
      closeTheRoom(container);
    });

    testWidgets('an english room names the play button «Play or pause your '
        'recording»', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
      final container = await entrarNaTraducao(tester, harness);

      expect(_playButtonEn(), findsOneWidget);
      closeTheRoom(container);
    });
  });
}
