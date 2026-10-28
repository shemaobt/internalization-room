import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'machine_generator.dart';
import 'the_back_translation_is_told_by_beads_test.dart' show entrarNaTraducao;

const _naoDeuParaConferir = 'não deu para conferir agora — tentem de novo';
const _couldNotCheck = 'couldn\'t check right now — try again';

const _part = PartSound(0, 'parte-0.m4a');

const _everyOtherStation = [
  Menu(),
  Canvas(),
  Panorama('panorama'),
  Ensaio(),
  ChecagemExterna(1),
  Fim(),
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

    test('a part that fails on every other Station tells nothing', () {
      for (final station in _everyOtherStation) {
        final (_, effects) = reduce(
          Machine(station: station, channel: const PartPlaying(_part)),
          PlayerFailed(_part.source, sound: _part),
        );

        expect(effects, isNot(contains(const TellThePlayFailed())));
      }
    });

    test('in every sequence a part that fails tells the screen only on the '
        'Back-translation', () {
      for (var seed = 0; seed < 50; seed++) {
        final random = Random(seed);
        var machine = const Machine(station: Retro());
        var world = const World();
        for (var step = 0; step < 40; step++) {
          if (machine.channel case PartPlaying(:final part)) {
            final (_, effects) = reduce(
              machine,
              PlayerFailed(part.source, sound: part),
            );
            expect(
              effects.contains(const TellThePlayFailed()),
              machine.station is Retro,
              reason:
                  'seed $seed, step $step: ${describeMachine(machine)} | '
                  '${effects.map(describeEffect).join(', ')}',
            );
          }
          final event = drawAnEvent(world, random);
          final (next, drawn) = reduce(machine, event);
          world = world.after(event, drawn);
          machine = next;
        }
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
  });
}
