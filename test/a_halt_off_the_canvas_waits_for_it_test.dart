import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

void main() {
  test('a halt raised on the scene rehearsal does not stand there, and rises '
      'once the team is back on the conversation', () {
    final (waiting, effects) = reduce(
      const Machine(station: SceneRehearsal()),
      const RoomRaisedAHalt(),
    );

    expect(
      waiting.halt,
      isA<NoHalt>(),
      reason: 'a parada cobria a cena, e o dela só fica sobre a conversa',
    );
    expect(effects, isEmpty);

    final (back, _) = reduce(waiting, const TheSceneRehearsalLeft());

    expect(back.station, isA<Canvas>());
    expect(back.halt, isA<Blocking>());
  });

  test('a halt raised on the external check does not stand there', () {
    final (waiting, effects) = reduce(
      const Machine(station: ChecagemExterna(1)),
      const RoomRaisedAHalt(),
    );

    expect(
      waiting.halt,
      isA<NoHalt>(),
      reason: 'a parada cobria a checagem, e o dela só fica sobre a conversa',
    );
    expect(waiting.aHaltWaitsForTheCanvas, isNotNull);
    expect(effects, isEmpty);
  });

  test('a halt raised on the back-translation does not stand there and calls '
      'nobody there', () {
    final (waiting, effects) = reduce(
      const Machine(station: Retro()),
      const RoomRaisedAHalt(),
    );

    expect(
      waiting.halt,
      isA<NoHalt>(),
      reason: 'a parada cobria a retro, e o Drafting dela nunca mostra o sinal',
    );
    expect(waiting.aHaltWaitsForTheCanvas, isNotNull);
    expect(effects, isEmpty);
  });

  test('a halt waiting from the back-translation rises once «pronto» takes the '
      'team to the conversation', () {
    final (waiting, _) = reduce(
      const Machine(station: Retro()),
      const RoomRaisedAHalt(),
    );

    final (onTheCanvas, effects) = reduce(waiting, const TheRecordingLeft());

    expect(onTheCanvas.station, isA<Canvas>());
    expect(onTheCanvas.halt, isA<Blocking>());
    expect(effects, contains(const CallForAPerson()));
  });

  test('a build guard halt waiting from the back-translation rises on the '
      'conversation calling nobody, as it would have there', () {
    final (waiting, _) = reduce(
      const Machine(station: Retro()),
      const RoomRaisedAHalt(callsForAPerson: false),
    );

    final (onTheCanvas, effects) = reduce(waiting, const TheRecordingLeft());

    expect(
      onTheCanvas.halt,
      isA<Blocking>().having((halt) => halt.callsNobody, 'callsNobody', true),
    );
    expect(
      effects,
      isNot(contains(const CallForAPerson())),
      reason: 'a espera esquecia que a parada do build não chama ninguém',
    );
  });

  test('a waiting halt that calls nobody does not quiet one that calls, in '
      'either order', () {
    const callsNobody = RoomRaisedAHalt(callsForAPerson: false);
    const calls = RoomRaisedAHalt();
    for (final (first, second) in [
      (callsNobody, calls),
      (calls, callsNobody),
    ]) {
      final (once, _) = reduce(const Machine(station: Retro()), first);
      final (twice, _) = reduce(once, second);

      final (_, effects) = reduce(twice, const TheRecordingLeft());

      expect(effects, contains(const CallForAPerson()));
    }
  });

  test('a halt waiting from the back-translation is let go once a line the '
      'room serves is heard there to its end', () {
    const verdict = Line(LineKind.guide, 1, url: '/voice/veredito');
    final (waiting, _) = reduce(
      const Machine(station: Retro(), channel: GuideSpeaking(verdict)),
      const RoomRaisedAHalt(),
    );

    final (heard, _) = reduce(waiting, const PlayerEnded(line: verdict));
    final (onTheCanvas, effects) = reduce(heard, const TheRecordingLeft());

    expect(heard.aHaltWaitsForTheCanvas, isNull);
    expect(
      onTheCanvas.halt,
      isA<NoHalt>(),
      reason:
          'o veredito ouvido de novo deixava a conversa chamar uma pessoa '
          'por uma resposta que a equipe já tinha ouvido',
    );
    expect(effects, isNot(contains(const CallForAPerson())));
  });

  test(
    'a bundled line heard on the back-translation keeps the halt waiting',
    () {
      const bundled = Line(
        LineKind.guide,
        2,
        fixedLine: (name: 'P2', language: 'pt'),
      );
      final (waiting, _) = reduce(
        const Machine(station: Retro(), channel: GuideSpeaking(bundled)),
        const RoomRaisedAHalt(),
      );

      final (heard, _) = reduce(waiting, const PlayerEnded(line: bundled));

      expect(heard.aHaltWaitsForTheCanvas, isNotNull);
    },
  );

  test('a halt waiting from the back-translation is dropped on the way to the '
      'ensaio or the check, not carried to a later conversation', () {
    final (waiting, _) = reduce(
      const Machine(station: Retro()),
      const RoomRaisedAHalt(),
    );

    final (onTheEnsaio, _) = reduce(waiting, const TheRehearsalOpened());
    final (onTheCheck, _) = reduce(waiting, const TheExternalCheckOpened(1));
    final (laterOnTheCanvas, _) = reduce(onTheEnsaio, const TheRecordingLeft());

    expect(onTheEnsaio.halt, isA<NoHalt>());
    expect(onTheCheck.halt, isA<NoHalt>());
    expect(onTheCheck.aHaltWaitsForTheCanvas, isNull);
    expect(
      laterOnTheCanvas.halt,
      isA<NoHalt>(),
      reason: 'a parada da retro subia numa conversa muito depois',
    );
  });

  test('a halt waiting from the external check is dropped when the team goes '
      'back to the back-translation, not carried to a later conversation', () {
    final (waiting, _) = reduce(
      const Machine(station: ChecagemExterna(1)),
      const RoomRaisedAHalt(),
    );

    final (back, _) = reduce(waiting, const TheExternalCheckLeft());
    final (onTheCanvas, _) = reduce(back, const TheRecordingLeft());

    expect(back.station, isA<Retro>());
    expect(back.halt, isA<NoHalt>());
    expect(
      onTheCanvas.halt,
      isA<NoHalt>(),
      reason: 'a parada da checagem subia numa conversa muito depois',
    );
  });
}
