import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, onAScreen, withRealLetters;

const _recordingHome = {
  'pt': 'Gravem o ensaio de vocês',
  'en': 'Record your rehearsal',
};

const _checkScreen = {
  'pt': 'Traduzir a gravação',
  'en': 'Translate the recording',
};

const _backToPassage = {
  'pt': 'Voltar para a passagem atual',
  'en': 'Back to the current passage',
};

const _backToRecording = {
  'pt': 'Voltar para a gravação',
  'en': 'Back to recording',
};

void _onAScreen(WidgetTester tester, double width, {double bar = 59}) =>
    onAScreen(tester, Size(width, 844), bar: bar);

Future<ProviderContainer> _atTheRecordingHome(
  WidgetTester tester,
  String language,
) async {
  final container = await pumpSala(tester, SalaHarness(lingua: language));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 300));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 1600));
  return container;
}

Future<ProviderContainer> _atTheCheckScreen(
  WidgetTester tester,
  String language,
) async {
  final container = await _atTheRecordingHome(tester, language);
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await untilTheAdvanceDiscLights(
    notifier,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pump(const Duration(milliseconds: 2400));
  return container;
}

void main() {
  setUpAll(withRealLetters);

  for (final language in ['pt', 'en']) {
    testWidgets(
      'the recording home\'s heading is one line on a 390 px phone, in '
      '$language',
      (tester) async {
        _onAScreen(tester, 390);
        final container = await _atTheRecordingHome(tester, language);

        expect(
          tester.getSize(find.text(_recordingHome[language]!)).height,
          lessThan(50),
          reason:
              'o título quebrava em duas linhas ao lado do botão do canto, e '
              'no app dela é uma linha só',
        );
        closeTheRoom(container);
      },
    );

    testWidgets('the check screen\'s heading is one line on a 390 px phone, in '
        '$language', (tester) async {
      _onAScreen(tester, 390);
      final container = await _atTheCheckScreen(tester, language);

      expect(
        tester.getSize(find.text(_checkScreen[language]!)).height,
        lessThan(50),
        reason: 'o título da conferência quebrava em duas linhas',
      );
      closeTheRoom(container);
    });

    testWidgets(
      'the corner button does not cover the recording home\'s heading on a '
      '390 px phone, in $language',
      (tester) async {
        _onAScreen(tester, 390);
        final container = await _atTheRecordingHome(tester, language);

        expect(
          tester
              .getRect(byLabel(_backToPassage[language]!))
              .overlaps(tester.getRect(find.text(_recordingHome[language]!))),
          isFalse,
          reason: 'o botão do canto ficava sobre o título da gravação',
        );
        closeTheRoom(container);
      },
    );

    testWidgets(
      'the corner button does not cover the check screen\'s heading on a '
      '390 px phone, in $language',
      (tester) async {
        _onAScreen(tester, 390);
        final container = await _atTheCheckScreen(tester, language);

        expect(
          tester
              .getRect(byLabel(_backToRecording[language]!))
              .overlaps(tester.getRect(find.text(_checkScreen[language]!))),
          isFalse,
          reason: 'o botão do canto ficava sobre o título da conferência',
        );
        closeTheRoom(container);
      },
    );
  }

  testWidgets(
    'on a 768 px tablet the recording home\'s heading starts 24 px below the '
    'top, as it always did',
    (tester) async {
      _onAScreen(tester, 768, bar: 0);
      final container = await _atTheRecordingHome(tester, 'pt');

      expect(
        tester.getTopLeft(find.text(_recordingHome['pt']!)).dy,
        24,
        reason: 'o título da gravação desceu num tablet, onde cabia ao lado',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'on a 768 px tablet the check screen\'s heading starts 24 px below the '
    'top, as it always did',
    (tester) async {
      _onAScreen(tester, 768, bar: 0);
      final container = await _atTheCheckScreen(tester, 'pt');

      expect(
        tester.getTopLeft(find.text(_checkScreen['pt']!)).dy,
        24,
        reason: 'o título da conferência desceu num tablet, onde cabia ao lado',
      );
      closeTheRoom(container);
    },
  );
}
