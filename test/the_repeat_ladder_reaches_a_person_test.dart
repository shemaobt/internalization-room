import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

const _threshold = Duration(milliseconds: 50);
const _longEnough = Duration(milliseconds: 90);

Future<void> _miss(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  notifier.conversaTap();
  await settle();
}

Future<void> _heard(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  await settle(_longEnough);
  notifier.conversaTap();
  await settle();
}

void main() {
  test('a second miss in a row calls for a person instead of a second line',
      () async {
    final harness = SalaHarness(shortestSpeech: _threshold);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();

    await _miss(notifier);
    await _miss(notifier);

    expect(
      harness.voice.assets,
      [
        fixedLineAsset(inaudibleLines.first, testLanguage),
        fixedLineAsset(needsPersonLine, testLanguage),
      ],
      reason: 'a primeira vez pede para repetir; a segunda chama alguém — '
          'nunca as duas linhas de repetir seguidas',
    );
    expect(container.read(salaSessionProvider).needsPerson, isTrue);
  });

  test('the ladder calls for a person that keeps the session, not a session '
      'that is gone', () async {
    final harness = SalaHarness(shortestSpeech: _threshold);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    final sessionId = container.read(salaSessionProvider).sessionId;

    await _miss(notifier);
    await _miss(notifier);

    expect(container.read(salaSessionProvider).sessionId, sessionId,
        reason: 'a sala pediu uma pessoa sem apagar a sessão — o círculo '
            'fica vivo, como ela concordou');
  });

  test('a turn the room heard resets the ladder', () async {
    final harness = SalaHarness(shortestSpeech: _threshold);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();

    await _miss(notifier);
    await _heard(notifier);
    harness.voice.assets.clear();
    await _miss(notifier);

    expect(
      harness.voice.assets,
      [fixedLineAsset(inaudibleLines.first, testLanguage)],
      reason: 'o turno ouvido zerou a escada — a próxima falta volta a '
          'pedir para repetir, não chama alguém direto',
    );
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });
}
