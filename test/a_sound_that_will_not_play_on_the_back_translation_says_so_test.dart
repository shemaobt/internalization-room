import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tocar,
        tocarNoCirculo;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;
import 'the_pause_snaps_to_silence_test.dart'
    show
        entrarComAFala,
        ouvirAPausa,
        pausarAos,
        s,
        traduzirEConfirmar,
        umaLacunaAos3;

const _naoDeuParaConferir = 'não deu para conferir agora — tentem de novo';
const _couldNotCheck = 'couldn\'t check right now — try again';

const _part = PartSound(0, 'parte-0.m4a');
const _stretch = StretchSound(
  'parte-0.m4a',
  from: Duration(seconds: 2),
  to: Duration(seconds: 4),
);

const _everyOtherStation = [
  Menu(),
  Canvas(),
  Panorama('panorama'),
  Ensaio(),
  ChecagemExterna(1),
  SceneRehearsal(),
];

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

int _linhasDitas(SalaHarness harness) =>
    harness.voice.sounds.where((sound) => sound.startsWith('voice:')).length;

void main() {
  group('the machine', () {
    test('a part that fails on the Back-translation tells the screen, calls '
        'nobody and says no line', () {
      final (machine, effects) = reduce(
        const Machine(station: Retro(), channel: PartPlaying(_part)),
        PlayerFailed(_part.source, sound: _part),
      );

      expect(effects, contains(const TellThePlayFailed()));
      expect(effects.whereType<CallForAPerson>(), isEmpty);
      expect(effects.whereType<PlayLine>(), isEmpty);
      expect(machine.channel, const Silence());
    });

    test('a stretch of the recording that fails on the Back-translation tells '
        'the screen', () {
      final (machine, effects) = reduce(
        const Machine(station: Retro(), channel: StretchPlaying(_stretch)),
        PlayerFailed(_stretch.source, sound: _stretch),
      );

      expect(effects, contains(const TellThePlayFailed()));
      expect(effects.whereType<CallForAPerson>(), isEmpty);
      expect(machine.channel, const Silence());
    });

    test('the team\'s own translation that fails tells nothing, as her own '
        'element is silent', () {
      const own = StretchSound(
        'traducao-1.m4a',
        named: 'trecho-1',
        telling: true,
      );
      final (machine, effects) = reduce(
        const Machine(station: Retro(), channel: StretchPlaying(own)),
        PlayerFailed(own.source, sound: own),
      );

      expect(effects, isNot(contains(const TellThePlayFailed())));
      expect(machine.channel, const Silence());
    });

    test('a sound that opens tells the screen nothing on any Station, so a '
        'play never takes her lines away', () {
      for (final station in [const Retro(), ..._everyOtherStation]) {
        final (_, effects) = reduce(
          Machine(station: station, channel: const PartPlaying(_part)),
          const PlayerOpened(),
        );

        expect(effects, const [ArmTheCeiling()]);
      }
    });
  });

  group('the screen', () {
    for (final (lingua, linha) in [
      ('pt', _naoDeuParaConferir),
      ('en', _couldNotCheck),
    ]) {
      testWidgets(
        '$lingua: a part that fails on the tell step writes her line, calls '
        'nobody and says nothing',
        (tester) async {
          _telaAlta(tester);
          final harness = SalaHarness(filaEmMemoria: true, lingua: lingua);
          final container = await entrarNaTraducao(tester, harness, partes: 1);
          await waitFor(
            'a parte tocar',
            () => container.read(salaSessionProvider).channel is PartPlaying,
            step: () => _passo(tester),
          );
          final ditas = _linhasDitas(harness);

          harness.playback.failPlayback();
          await _passo(tester);
          await _passo(tester);

          expect(find.text(linha), findsOneWidget);
          expect(container.read(salaSessionProvider).needsPerson, isFalse);
          expect(harness.room.personsAsked, 0);
          expect(
            _linhasDitas(harness),
            ditas,
            reason: 'nenhuma linha foi dita',
          );
          closeTheRoom(container);
        },
      );
    }

    testWidgets('«ouvir a pausa» that fails writes her line', (tester) async {
      _telaAlta(tester);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarComAFala(tester, harness, umaLacunaAos3);
      await pausarAos(tester, harness, s(4.2));
      await tocar(tester, ouvirAPausa);
      expect(find.text(_naoDeuParaConferir), findsNothing);

      harness.playback.failPlayback();
      await _passo(tester);
      await _passo(tester);

      expect(find.text(_naoDeuParaConferir), findsOneWidget);
      expect(container.read(salaSessionProvider).needsPerson, isFalse);
      closeTheRoom(container);
    });

    testWidgets('the sentence heard before it is recorded again that fails '
        'writes nothing, and her line to record it comes', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await quatroFrasesEmWav(tester, harness);
      await tocar(tester, 'regravar a frase 3');
      expect(harness.playback.ranges.last, '0-4000');

      harness.playback.failPlayback();
      await _passo(tester);
      await tester.pump(const Duration(seconds: 9));
      await _passo(tester);

      expect(find.text(_naoDeuParaConferir), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RetroView),
          matching: find.text('gravem a frase inteira'),
        ),
        findsOneWidget,
      );
      closeTheRoom(container);
    });

    testWidgets('«ouvir a pausa» that plays after one that failed leaves her '
        'line standing', (tester) async {
      _telaAlta(tester);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarComAFala(tester, harness, umaLacunaAos3);
      await pausarAos(tester, harness, s(4.2));
      await tocar(tester, ouvirAPausa);
      harness.playback.failPlayback();
      await _passo(tester);
      expect(find.text(_naoDeuParaConferir), findsOneWidget);

      await tocar(tester, ouvirAPausa);
      await _passo(tester);

      expect(harness.playback.sounding, isTrue);
      expect(find.text(_naoDeuParaConferir), findsOneWidget);

      await traduzirEConfirmar(tester);

      expect(find.text(_naoDeuParaConferir), findsNothing);
      closeTheRoom(container);
    });

    testWidgets('a check that could not run keeps her line over a sentence '
        'played after it', (tester) async {
      _telaAlta(tester);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await gravarATraducao(tester);
      await contarAteOFimDaParte(tester, harness);
      await waitFor(
        'o terminei acender',
        () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
        step: () => _passo(tester),
      );
      harness.room.verdictRefusal = CheckRefusal.checkUnavailable;
      await tocar(tester, conferir);
      await waitFor(
        'a conferência voltar sem conferir',
        () =>
            container.read(salaSessionProvider).btRecusa ==
            CheckRefusal.checkUnavailable,
        step: () => _passo(tester),
      );
      await _passo(tester);
      expect(find.text(_naoDeuParaConferir), findsOneWidget);
      final tocadas = harness.playback.played.length;

      await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');
      await waitFor(
        'a frase tocar',
        () =>
            harness.playback.played.length > tocadas &&
            harness.playback.sounding,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(find.text(_naoDeuParaConferir), findsOneWidget);
      closeTheRoom(container);
    });
  });
}
