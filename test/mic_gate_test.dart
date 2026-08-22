import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:internalization_room/features/sala/data/mic_permission.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'session_notifier_test.dart' show inConversa, settle;

void main() {
  test('a refused microphone is noticed before anything is recorded', () async {
    final harness = SalaHarness()..recorder.permitted = false;
    final container = harness.container();
    addTearDown(container.dispose);

    final access = await container.read(micPermissionProvider.notifier).check();

    expect(access, MicAccess.denied);
  });

  test('a granted microphone leaves the room open', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    expect(await container.read(micPermissionProvider.notifier).check(), MicAccess.granted);
  });

  test('a recording that never started closes the room instead of failing quietly', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa();
    await settle();

    harness.recorder.permitted = false;
    notifier.conversaTap();
    await settle();

    expect(container.read(micPermissionProvider), MicAccess.denied,
        reason: 'a equipe falaria a passagem inteira contra um gravador que nunca ligou');
  });

  test('the team is told, in the facilitator voice, from the bundle', () async {
    final harness = SalaHarness()..recorder.permitted = false;
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(micPermissionProvider.notifier).check();
    await container.read(facilitatorVoiceProvider).playAsset('assets/audio/microfone.mp3');

    expect(harness.voice.assets, ['assets/audio/microfone.mp3']);
    expect(harness.room.calls, isEmpty, reason: 'o aviso não pode depender de rede');
  });

  test('a recorder that will not start is not a team that said no', () async {
    final harness = SalaHarness()..recorder.startThrows = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(container.read(micPermissionProvider), isNot(MicAccess.denied),
        reason: 'disco cheio não é a equipe negando o microfone');
    expect(state.needsPerson, isTrue);
    expect(state.voice, isNot(VoiceState.listening),
        reason: 'a tela dizia que a sala estava ouvindo, com o gravador desligado');
  });

  test('a permission question that never comes back is not a refusal', () async {
    final harness = SalaHarness()..recorder.answersPermission = null;
    final container = harness.container();
    addTearDown(container.dispose);

    final access = await container.read(micPermissionProvider.notifier).check();

    expect(access, MicAccess.unknown,
        reason: 'sessenta segundos sem resposta da plataforma punham a equipe na tela de '
            'microfone negado, sem ninguém ter negado nada');
  });
}
