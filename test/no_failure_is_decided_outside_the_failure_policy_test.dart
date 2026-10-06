import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _theNotifier = 'lib/features/sala/data/session_notifier.dart';

const _intoTheMapper = [
  '_decideTheFailure(',
  '_decideAt(',
  '_outOfReach(',
  '_theStepFell(',
  '_theResumeFell(',
  '_theSessionIsGone(',
  '_giveUpOnTheTurn(',
  'rethrow',
];

/// Doors whose room failures still decide on their own, each with the ticket that
/// moves it into the failure policy.
const _notYetMoved = <String, String>{
  '_anEarlierSessionAnswered': 'ENG-1354',
  '_tellTheRoomAPersonArrivedAt': 'ENG-1354',
  '_aprovarRascunhoFinal': 'ENG-1444',
  '_asPartesDaSala': 'ENG-1444',
  '_createThePassage': 'ENG-1444',
  '_finishBackTranslation': 'ENG-1444',
  '_goConversa': 'ENG-1444',
  '_porCadaTrechoNaSuaParte': 'ENG-1444',
  '_tellThatStretchAgain': 'ENG-1444',
  '_theTranslationWaits': 'ENG-1444',
  '_watchCoverageChannel': 'ENG-1444',
};

final _namesAFailure = RegExp(
  r'\b(NetworkFailed|Refused|SessionGone)\b|\bRoomFailure\b',
);

final _aMethod = RegExp(r'^  (?![\s/])[\w<>?, ]*?\b(_?\w+)\(', multiLine: true);

/// Where a case's pattern ends: at its colon in a switch, or at the parenthesis that
/// closes an `if (… case …)`.
int _patternEnd(String source, int from) {
  var depth = 0;
  for (var at = from; at < source.length; at++) {
    final char = source[at];
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    if (depth < 0 || (char == ':' && depth == 0)) return at;
  }
  return -1;
}

int _blockEnd(String source, int from) {
  final opening = source.indexOf(RegExp(r'\S'), from);
  if (source[opening] != '{') return source.indexOf(';', from);
  var depth = 0;
  for (var at = opening; at < source.length; at++) {
    if (source[at] == '{') depth++;
    if (source[at] == '}' && --depth == 0) return at;
  }
  return source.length;
}

int _armEnd(String source, int from) {
  var depth = 0;
  for (var at = from; at < source.length; at++) {
    final char = source[at];
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) {
      if (depth == 0) return at;
      depth--;
    }
    if (depth == 0 &&
        (source.startsWith('case ', at) || source.startsWith('default:', at))) {
      return at;
    }
  }
  return source.length;
}

String? _methodAround(String source, int at) {
  String? name;
  for (final method in _aMethod.allMatches(source)) {
    if (method.start > at) break;
    name = method.group(1);
  }
  return name;
}

bool _handsItOn(String body, String? name) {
  if (_intoTheMapper.any(body.contains)) return true;
  return name != null &&
      RegExp('(return|throw)\\s+$name\\b|[(,]\\s*$name\\s*[),]').hasMatch(body);
}

List<String> _failuresCaughtOutsideTheMapper(String source) {
  final found = <String>[];
  for (final arm in RegExp(r'\bcase\s').allMatches(source)) {
    final colon = _patternEnd(source, arm.end);
    if (colon < 0) continue;
    final pattern = source.substring(arm.end, colon);
    if (!_namesAFailure.hasMatch(pattern)) continue;
    final method = _methodAround(source, arm.start);
    if (_notYetMoved.containsKey(method)) continue;
    final bound = RegExp(
      r'final\s+(?:\w+\s+)?(\w+)\s*$',
    ).firstMatch(pattern.split(' when ').first.split('&&').last.trim());
    final body = source.substring(
      colon + 1,
      source[colon] == ':'
          ? _armEnd(source, colon + 1)
          : _blockEnd(source, colon + 1),
    );
    if (_handsItOn(body, bound?.group(1))) continue;
    found.add('$method: case${pattern.trim()}');
  }
  for (final clause in RegExp(
    r'\bon\s+(?:RoomFailure|NetworkFailed|Refused|SessionGone)\b'
    r'(?:\s+catch\s*\((\w+)[^)]*\))?\s*\{',
  ).allMatches(source)) {
    final method = _methodAround(source, clause.start);
    if (_notYetMoved.containsKey(method)) continue;
    final body = source.substring(
      clause.end,
      _blockEnd(source, clause.end - 1),
    );
    if (_handsItOn(body, clause.group(1))) continue;
    found.add('$method: ${clause.group(0)!.trim()}');
  }
  return found;
}

const _thePolicy = 'lib/features/sala/domain/failure_policy.dart';
const _theMachine = 'lib/features/sala/domain/machine.dart';

const _whatOnlyThePolicyDecides = [
  'TheRoomAnswered',
  'NetworkFailedAt',
  'TheSessionIsGone',
  'TurnGivenUp',
  'TheRoomRefused',
  'ThePassageCannotOpen',
];

final _comment = RegExp(r'//.*$', multiLine: true);

Iterable<File> get _theRoomsCode => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  test('No failure is decided outside the failure policy.', () {
    final decidedElsewhere = <String>[];
    for (final file in _theRoomsCode) {
      final source = file.readAsStringSync().replaceAll(_comment, '');
      if (source.contains('_handleRoomFailure')) {
        decidedElsewhere.add('${file.path}: _handleRoomFailure');
      }
      if (file.path == _thePolicy || file.path == _theMachine) continue;
      for (final event in _whatOnlyThePolicyDecides) {
        if (RegExp('\\b$event\\(').hasMatch(source)) {
          decidedElsewhere.add('${file.path}: $event');
        }
      }
    }

    expect(
      decidedElsewhere,
      isEmpty,
      reason:
          'a room result reaches the machine only as the event '
          'FailurePolicy.decide makes of it',
    );
  });

  test(
    'No room failure is caught outside the one mapper into a room result.',
    () {
      expect(
        _failuresCaughtOutsideTheMapper(
          File(_theNotifier).readAsStringSync().replaceAll(_comment, ''),
        ),
        isEmpty,
        reason:
            'a door that catches a room failure and acts on it itself is a '
            'failure decided outside the policy; a door not moved yet is named '
            'with the ticket that moves it',
      );
    },
  );
}
