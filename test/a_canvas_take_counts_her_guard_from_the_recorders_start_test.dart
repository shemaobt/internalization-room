import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _herGuard = CaptureGuard(
  minDuration: Duration(milliseconds: 700),
  minBytes: 1,
);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;
  final bool onThePanorama;

  _Room(this.harness, this.container, {this.onThePanorama = false});

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  Future<void> tap() async {
    if (onThePanorama) {
      notifier.panoramaTap();
    } else {
      notifier.conversaTap();
    }
    await settle();
  }
}

Future<void> _onAClock(
  Future<void> Function(void Function(Duration) later) body,
) async {
  var now = DateTime(2026, 10, 29);
  var step = const Duration(seconds: 1);
  await withClock(Clock(() => now = now.add(step)), () async {
    await body((by) {
      step = Duration.zero;
      now = now.add(by);
    });
  });
}

Future<_Room> _inConversa(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  return _Room(harness, container);
}

Future<_Room> _onThePanorama(SalaHarness harness) async {
  harness.room.passages = [_panorama, ...harness.room.passages];
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container, onThePanorama: true);
  await enterThePanorama(room.notifier, () => room.state);
  await waitFor(
    'o panorama ser dito e a sala voltar ao convite',
    () => room.state.panoramaSaid && room.state.voice == VoiceState.invite,
  );
  return room;
}

void main() {
  test('a recorder that answers half a second late still holds the take '
      'against a stop tap 0.4 s after it started', () async {
    await _onAClock((later) async {
      final room = await _inConversa(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;
      room.harness.recorder.holdNextStart();

      await room.tap();
      later(const Duration(milliseconds: 500));
      room.harness.recorder.finishStart();
      await settle();
      later(const Duration(milliseconds: 400));
      await room.tap();

      expect(
        room.state.voice,
        VoiceState.listening,
        reason:
            'a janela contava do toque, e o atraso do gravador já tinha '
            'gastado o tempo dela',
      );
      await settle();
      expect(room.harness.room.turnsSent, turns);

      later(const Duration(milliseconds: 400));
      await room.tap();
      await waitFor(
        'a vez chegar à sala',
        () => room.harness.room.turnsSent == turns + 1,
      );
    });
  });

  test('a tap on the conversation while its stop is still in flight stops '
      'nothing again, and the take goes to the room once', () async {
    await _onAClock((later) async {
      final room = await _inConversa(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;

      await room.tap();
      later(const Duration(milliseconds: 800));
      room.harness.recorder.holdNextStop();
      await room.tap();
      later(const Duration(milliseconds: 100));
      await room.tap();
      expect(room.state.voice, VoiceState.listening);

      room.harness.recorder.finishStop();
      await waitFor(
        'a vez chegar à sala',
        () => room.harness.room.turnsSent > turns,
      );
      await settle();

      expect(
        room.harness.sounds.where((sound) => sound == 'recorder:stop'),
        hasLength(1),
        reason:
            'o segundo toque, com a parada ainda em curso, pedia ao gravador '
            'uma segunda parada',
      );
      expect(
        room.harness.room.turnsSent,
        turns + 1,
        reason: 'a mesma vez subia duas vezes',
      );
      expect(room.harness.recorder.starts, hasLength(1));
    });
  });

  test('a tap on the Panorama while its stop is still in flight stops nothing '
      'again either, and the take goes to the room once', () async {
    await _onAClock((later) async {
      final room = await _onThePanorama(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;

      await room.tap();
      later(const Duration(milliseconds: 800));
      room.harness.recorder.holdNextStop();
      await room.tap();
      later(const Duration(milliseconds: 100));
      await room.tap();
      expect(room.state.voice, VoiceState.listening);

      room.harness.recorder.finishStop();
      await waitFor(
        'a vez do Panorama chegar à sala',
        () => room.harness.room.turnsSent > turns,
      );
      await settle();

      expect(
        room.harness.sounds.where((sound) => sound == 'recorder:stop'),
        hasLength(1),
        reason:
            'no Panorama o segundo toque, com a parada ainda em curso, pedia '
            'ao gravador uma segunda parada',
      );
      expect(
        room.harness.room.turnsSent,
        turns + 1,
        reason: 'a mesma vez do Panorama subia duas vezes',
      );
      expect(room.harness.recorder.starts, hasLength(1));
    });
  });

  test('a tap on the circle while the raised hand\'s question is still being '
      'stopped stops nothing again, and the question goes out alone', () async {
    await _onAClock((later) async {
      final room = await _inConversa(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;
      room.notifier.handTap();
      await settle();
      expect(room.state.noteMode, isTrue);

      await room.tap();
      later(const Duration(milliseconds: 800));
      room.harness.recorder.holdNextStop();
      await room.tap();
      expect(room.state.noteMode, isFalse);
      later(const Duration(milliseconds: 100));
      await room.tap();

      room.harness.recorder.finishStop();
      await waitFor(
        'a pergunta chegar à mesa',
        () => room.harness.inbox.questionsSent.isNotEmpty,
      );
      await settle();

      expect(
        room.harness.sounds.where((sound) => sound == 'recorder:stop'),
        hasLength(1),
        reason:
            'o toque com a pergunta ainda sendo parada pedia ao gravador uma '
            'segunda parada, a do círculo',
      );
      expect(room.harness.inbox.questionsSent, hasLength(1));
      expect(
        room.harness.room.turnsSent,
        turns,
        reason: 'o áudio da pergunta subia também como uma vez da conversa',
      );
      expect(room.harness.recorder.starts, hasLength(1));
    });
  });

  test('a double tap on the Panorama keeps the take going and sends nothing, '
      'as on the conversation', () async {
    await _onAClock((later) async {
      final room = await _onThePanorama(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;

      await room.tap();
      later(const Duration(milliseconds: 200));
      await room.tap();

      expect(
        room.state.voice,
        VoiceState.listening,
        reason: 'no Panorama o segundo toque de um toque duplo encerrava a vez',
      );
      await settle();
      expect(
        room.harness.room.turnsSent,
        turns,
        reason: 'a vez de 0,2 s do Panorama ia para a sala',
      );

      later(const Duration(milliseconds: 800));
      await room.tap();
      await waitFor(
        'a vez do Panorama chegar à sala',
        () => room.harness.room.turnsSent == turns + 1,
      );
    });
  });

  test('a tap on the Panorama while its recorder is still starting does '
      'nothing, and the take records once it answers', () async {
    await _onAClock((later) async {
      final room = await _onThePanorama(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;
      room.harness.recorder.holdNextStart();

      await room.tap();
      later(const Duration(seconds: 2));
      await room.tap();
      room.harness.recorder.finishStart();
      await settle();

      expect(
        room.state.voice,
        VoiceState.listening,
        reason:
            'o toque com o gravador ainda abrindo fechava o microfone antes '
            'de ele começar',
      );
      expect(room.state.takeRecordingSince, isNotNull);
      expect(room.harness.room.turnsSent, turns);
    });
  });

  test('a ghost take on the Panorama is thrown away with nothing sent, and '
      'the circle goes back to rest, as on the conversation', () async {
    await _onAClock((later) async {
      final room = await _onThePanorama(
        SalaHarness(
          captureGuard: const CaptureGuard(
            minDuration: Duration(milliseconds: 700),
            minBytes: 800,
          ),
        ),
      );
      final turns = room.harness.room.turnsSent;

      await room.tap();
      later(const Duration(milliseconds: 800));
      await room.tap();
      await settle();

      expect(
        room.harness.room.turnsSent,
        turns,
        reason: 'no Panorama uma vez sem nada para dizer ia para a sala',
      );
      expect(room.harness.recorder.deleted, [room.harness.recorder.lastPath]);
      expect(room.state.voice, VoiceState.invite);
      expect(room.state.awaitingTheGuide, isFalse);
    });
  });

  test('a question whose recorder answered late is sent whatever it '
      'measured: the hand holds a question to no window', () async {
    await _onAClock((later) async {
      final room = await _inConversa(SalaHarness(captureGuard: _herGuard));
      room.notifier.handTap();
      await settle();
      expect(room.state.noteMode, isTrue);
      room.harness.recorder.holdNextStart();

      await room.tap();
      later(const Duration(milliseconds: 500));
      room.harness.recorder.finishStart();
      await settle();
      later(const Duration(milliseconds: 400));
      await room.tap();
      await waitFor(
        'a pergunta chegar à mesa',
        () => room.harness.inbox.questionsSent.isNotEmpty,
      );

      expect(
        room.harness.inbox.questionsSent,
        hasLength(1),
        reason:
            'a mão apagava uma pergunta de verdade por ela durar menos de '
            '0,7 s, contada do gravador ou do toque',
      );
    });
  });
}
