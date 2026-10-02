import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fakes.dart';

const _line = Line(LineKind.guide, 1);

final _everyEffect = <Effect>[
  const SilenceTheRoom(),
  const CloseAndDiscardTheMic(),
  const ArmTheWatch(),
  const CallForAPerson(),
  const StopCallingForAPerson(),
  const TellAPersonArrived(),
  const ReadTheState(),
  const ReplayTheSound(ThePart()),
  const AskTheOpeningAgain('turn-2'),
  const PlayLine(_line),
  const PlayPart(PartSound(0, 'part.m4a')),
  const PlayStretch(StretchSound('stretch.m4a')),
  const OpenTheMic(MicOwner.conversation, take: 'take.m4a'),
  const StopTheLine(_line),
  const DropTheLine(_line),
  const StopTheSound(),
  const HoldTheSound(),
  const LetTheSoundRun(),
  const ArmTheRetry(step: 0, due: Duration(seconds: 1)),
  const CancelTheRetry(),
  const DrainTheOutbox(),
  const ResendPending(),
  const ProbeTheRoom(),
  const SayTheOfflineNotice(),
  const DiscardTheSession(),
  const OpenTheChoice(),
];

void main() {
  for (final effect in _everyEffect.where((e) => e is! CancelTheRetry)) {
    test('the runner does something for ${effect.runtimeType}', () {
      fakeAsync((time) {
        final harness = SalaHarness();
        final container = ProviderContainer(overrides: harness.overrides);
        final host = ARoomHost();
        final runner = EffectRunner(
          room: container.read(roomPortProvider),
          sound: container.read(soundPortProvider),
          recorder: container.read(recorderPortProvider),
          store: container.read(storePortProvider),
          host: host,
          watchPeriod: () => const Duration(seconds: 30),
          retryDelay: (_) => const Duration(seconds: 1),
        );

        runner.run([effect]);

        final acted =
            host.asked.isNotEmpty ||
            harness.sounds.isNotEmpty ||
            time.nonPeriodicTimerCount > 0;
        expect(acted, isTrue);
        runner.dispose();
        container.dispose();
      });
    });
  }

  test('the runner cancels a retry it armed', () {
    fakeAsync((time) {
      final container = ProviderContainer(overrides: SalaHarness().overrides);
      final runner = EffectRunner(
        room: container.read(roomPortProvider),
        sound: container.read(soundPortProvider),
        recorder: container.read(recorderPortProvider),
        store: container.read(storePortProvider),
        host: ARoomHost(),
        watchPeriod: () => const Duration(seconds: 30),
        retryDelay: (_) => const Duration(seconds: 1),
      );
      runner.run(const [ArmTheRetry(due: Duration(seconds: 1))]);
      expect(time.nonPeriodicTimerCount, 1);

      runner.run(const [CancelTheRetry()]);

      expect(time.nonPeriodicTimerCount, 0);
      container.dispose();
    });
  });
}
