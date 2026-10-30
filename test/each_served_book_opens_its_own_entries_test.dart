import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'served_books.dart';

SalaHarness _aRoomServing(List<String> books) => SalaHarness()
  ..room.books = books
  ..room.passagesOfBook = {
    'Esther': estherList,
    'Jonah': jonahList,
    'Ruth': ruthList,
  };

class _Tablet {
  final SalaHarness harness;
  final ProviderContainer container;

  _Tablet(this.harness, this.container);

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  int asked(String call) =>
      harness.room.calls.where((asked) => asked == call).length;

  Future<void> onTheChoice() async {
    await notifier.abrirEscolha();
    await theChoiceOffersAPassage(container);
  }

  Future<void> tap(String pericope) async {
    if (!state.entriesOpen) await onTheChoice();
    notifier.openTheEntry(
      state.naRoda!.singleWhere((entry) => entry.pericope == pericope),
    );
    await waitFor(
      '$pericope to open',
      () =>
          !state.awaitingTheGuide &&
          state.voice == VoiceState.invite &&
          (state.sessionId ?? state.panoramaSessionId) != null,
    );
    await settle();
  }

  Future<void> leave() async {
    notifier.leaveThePassage();
    await theChoiceOffersAPassage(container);
  }
}

_Tablet _aTablet([List<String> books = servedBooks]) {
  final harness = _aRoomServing(books);
  final container = harness.container();
  addTearDown(container.dispose);
  return _Tablet(harness, container);
}

void main() {
  group(
    'a failed read of the room\'s books is a failed Wheel, with its retry',
    () {
      test(
        'an offline answer: the touch is the retry, and it fills the Wheel',
        () async {
          final tablet = _aTablet()
            ..harness.room.failBooksWith = const NetworkFailed('timeout');

          await tablet.notifier.abrirEscolha();
          await settle();

          expect(tablet.state.rodaPorLer, isTrue);
          expect(tablet.state.livroInteiroFeito, isFalse);

          tablet.harness.room.failBooksWith = null;
          tablet.notifier.escolhaTap();
          await theChoiceOffersAPassage(tablet.container);

          expect(tablet.state.naRoda, [
            ...estherList,
            ...jonahList,
            ...ruthList,
          ]);
        },
      );

      test(
        'a refusal: the Wheel stays unread, nobody is called, and the touch is '
        'the retry',
        () async {
          final tablet = _aTablet()
            ..harness.room.failBooksWith = const Refused('BAD_REQUEST');

          await tablet.notifier.abrirEscolha();
          await settle();

          expect(tablet.state.rodaPorLer, isTrue);
          expect(tablet.state.livroInteiroFeito, isFalse);
          expect(tablet.state.needsPerson, isFalse);

          tablet.harness.room.failBooksWith = null;
          tablet.notifier.escolhaTap();
          await theChoiceOffersAPassage(tablet.container);

          expect(tablet.state.naRoda, [
            ...estherList,
            ...jonahList,
            ...ruthList,
          ]);
        },
      );
    },
  );

  test(
    'one book\'s list that fails is a failed Wheel, with no partial menu',
    () async {
      final tablet = _aTablet()
        ..harness.room.failPassagesOf['Jonah'] = const NetworkFailed('timeout');

      await tablet.notifier.abrirEscolha();
      await settle();

      expect(tablet.state.naRoda, isNull);
      expect(tablet.state.rodaPorLer, isTrue);
      expect(tablet.state.entriesOpen, isFalse);
    },
  );

  test('tapping Jonas\'s Panorama asks the room for OV-Jonah', () async {
    final tablet = _aTablet();

    await tablet.tap('OV-Jonah');

    expect(tablet.harness.room.pericopesAsked, ['OV-Jonah']);
  });

  test(
    'tapping Rute\'s Panorama asks the room for OV-Ruth, never the OV alias',
    () async {
      final tablet = _aTablet();

      await tablet.tap('OV-Ruth');

      expect(tablet.harness.room.pericopesAsked, ['OV-Ruth']);
    },
  );

  test('a Ruth Panorama the team left is not reused for Jonah\'s', () async {
    final tablet = _aTablet();
    await tablet.tap('OV-Ruth');
    await tablet.leave();

    await tablet.tap('OV-Jonah');

    final room = tablet.harness.room;
    expect(room.pericopesAsked, ['OV-Ruth', 'OV-Jonah']);
    expect(room.sessionIds, hasLength(2));
    expect(tablet.state.panoramaSessionId, room.sessionIds.last);
    expect(room.sessionsSpokenTo.last, room.sessionIds.last);
  });

  test('a passage left tints its own book\'s pill only, when another book '
      'holds a passage of the same id', () async {
    final tablet = _aTablet(const ['Jonah', 'Ruth']);
    tablet.harness.room.passagesOfBook = {
      for (final book in ['Jonah', 'Ruth'])
        book: [Passagem(pericope: 'P01', audioUrl: '', book: book)],
    };
    await tablet.onTheChoice();
    Passagem p01Of(String book) =>
        tablet.state.naRoda!.singleWhere((entry) => entry.book == book);
    tablet.notifier.openTheEntry(p01Of('Jonah'));
    await waitFor(
      'Jonah\'s P01 to open',
      () => tablet.state.sessionId != null && !tablet.state.awaitingTheGuide,
    );

    await tablet.leave();

    expect(tablet.state.isTheEntryLeft(p01Of('Jonah')), isTrue);
    expect(
      tablet.state.isTheEntryLeft(p01Of('Ruth')),
      isFalse,
      reason: 'a P01 de Rute ficava marcada como a passagem deixada',
    );
  });

  test(
    'a passage opened after another book\'s Panorama names no session before it',
    () async {
      final tablet = _aTablet();
      await tablet.tap('OV-Ruth');
      await tablet.leave();

      await tablet.tap('J01');

      expect(tablet.harness.room.pericopesAsked.last, 'J01');
      expect(tablet.harness.room.metBefore.last, isFalse);
    },
  );

  test(
    'tapping a Jonah passage opens it, and a relaunch lands on it',
    () async {
      final tablet = _aTablet();
      await tablet.tap('J01');
      final session = tablet.state.sessionId;

      expect(tablet.harness.room.pericopesAsked, ['J01']);

      final (harness, container) = await relaunch(
        tablet.harness,
        tablet.container,
      );
      final again = _Tablet(harness, container);
      await again.notifier.openTheRoom();
      await waitFor(
        'the team to land on J01',
        () => again.state.sessionId == session && !again.state.awaitingTheGuide,
      );

      expect(again.state.station, isA<Canvas>());
      expect(again.asked('createSession'), 1);
    },
  );

  test(
    'work kept in a Jonah passage is found again when the team returns to it',
    () async {
      final tablet = _aTablet();
      await tablet.tap('J01');
      final j01 = tablet.state.sessionId;
      await waitFor(
        'J01 to keep its place',
        () => tablet.harness.emAberto.rows.containsKey('Jonah/J01/pt'),
      );
      await tablet.leave();
      await tablet.tap('P01');
      await tablet.leave();

      await tablet.tap('J01');

      expect(tablet.state.sessionId, j01);
      expect(tablet.harness.room.pericopesAsked, ['J01', 'P01', 'J01']);
    },
  );

  test('work Ruth kept before this change is found again', () async {
    final tablet = _aTablet();
    tablet.harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-guardada',
      stage: SalaStage.conversa,
    );

    await tablet.tap('P02');

    expect(tablet.state.sessionId, 'sessao-guardada');
    expect(tablet.harness.room.pericopesAsked, ['P02']);
  });

  test('opening the room on a halted Choice with nothing on the Wheel asks the '
      'room nothing', () async {
    final tablet = _aTablet()
      ..harness.room.failBooksWith = const Refused('BAD_REQUEST');
    await tablet.notifier.openTheRoom();
    await settle();
    tablet.notifier.haltForABrokenBuild();
    expect(tablet.state.needsPerson, isTrue);
    expect(tablet.state.naRoda, isNull);
    final booksRead = tablet.asked('servedBooks');
    final listsRead = tablet.asked('passagesOf');
    expect(booksRead, greaterThan(0));

    await tablet.notifier.openTheRoom();
    await settle();

    expect(tablet.asked('servedBooks'), booksRead);
    expect(tablet.asked('passagesOf'), listsRead);
    expect(tablet.state.needsPerson, isTrue);
  });
}
