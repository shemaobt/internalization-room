import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

void main() {
  test('session starts at convite with an inviting voice', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);

    expect(state.stage, SalaStage.convite);
    expect(state.voice, VoiceState.invite);
    expect(state.conviteStep, ConviteStep.boasVindas);
    expect(state.engaged, 0);
    expect(state.colarOn, isFalse);
  });

  test('ping range covers newly engaged beads only', () {
    const ping = PingRange(4, 6);

    expect(ping.contains(3), isFalse);
    expect(ping.contains(4), isTrue);
    expect(ping.contains(5), isTrue);
    expect(ping.contains(6), isFalse);
  });

  test('conversaDone requires full coverage and an idle voice', () {
    const partial = SalaSessionState(
      stage: SalaStage.conversa,
      engaged: 10,
    );
    const covered = SalaSessionState(
      stage: SalaStage.conversa,
      engaged: 12,
    );
    const speaking = SalaSessionState(
      stage: SalaStage.conversa,
      engaged: 12,
      voice: VoiceState.speaking,
    );

    expect(partial.conversaDone, isFalse);
    expect(covered.conversaDone, isTrue);
    expect(speaking.conversaDone, isFalse);
  });
}
