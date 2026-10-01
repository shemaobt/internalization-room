import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _doorsOfTheRoom = [
  'lib/features/sala/data/session_notifier.dart',
  'lib/features/sala/data/take_upload_queue.dart',
];

const _theReach = [
  '_outOfReach(',
  '_fellOnTheNetwork(',
  '_theStepFell(',
  '_theResumeFell(',
];

final _commentPattern = RegExp(r'//.*$', multiLine: true);
final _typeTest = RegExp(
  r'\bis!?\s+(Answered|RoomFailure|NetworkFailed|Refused|SessionGone)\b',
);
final _expressionArm = RegExp(r'\b(NetworkFailed\(\)|RoomFailure\b)[^;{}:]*=>');

String _withoutComments(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

int _lineOf(String source, int at) =>
    '\n'.allMatches(source.substring(0, at)).length + 1;

int _patternEnd(String source, int from) {
  var depth = 0;
  for (var at = from; at < source.length; at++) {
    final char = source[at];
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    if (depth < 0) return -1;
    if (char == ':' && depth == 0) return at;
  }
  throw StateError('a case with no colon after $from');
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

final _speaks = RegExp(r'\b_(voice\.|say)');
final _genericCatch = RegExp(r'\bon\s+(Exception|Object)\b|\bcatch\s*\(');
final _namedFailure = RegExp(r'\bon\s+(RoomFailure|NetworkFailed)\b');

int _closingBrace(String source, int opening) {
  var depth = 0;
  for (var at = opening; at < source.length; at++) {
    if (source[at] == '{') depth++;
    if (source[at] == '}' && --depth == 0) return at;
  }
  throw StateError('unbalanced braces after $opening');
}

int _clausesEnd(String source, int tryEnd) {
  var at = tryEnd + 1;
  while (true) {
    final clause = RegExp(
      r'^\s*(on\s+\w+[^{]*|catch\s*\([^)]*\))\s*\{',
    ).firstMatch(source.substring(at));
    if (clause == null) return at;
    at = _closingBrace(source, at + clause.end - 1) + 1;
  }
}

bool _handsItOn(String body, String? name) {
  if (_theReach.any(body.contains) || body.contains('rethrow')) return true;
  return name != null &&
      RegExp('(return|throw)\\s+$name\\b|[(,]\\s*$name\\s*[),]').hasMatch(body);
}

List<String> _armsThatSwallowTheNetwork(String source) {
  final found = <String>[];
  for (final arm in RegExp(r'\bcase\s').allMatches(source)) {
    final colon = _patternEnd(source, arm.end);
    if (colon < 0) continue;
    final pattern = source.substring(arm.end, colon);
    final namesTheNetwork = pattern.contains('NetworkFailed()');
    final bound = RegExp(
      r'final\s+(?:RoomFailure\s+)?(\w+)\s*$',
    ).firstMatch(pattern.split(' when ').first.trim());
    final catchesEveryFailure = pattern.contains('RoomFailure');
    if (!namesTheNetwork && !catchesEveryFailure) continue;
    final body = source.substring(colon + 1, _armEnd(source, colon + 1));
    if (_handsItOn(body, bound?.group(1))) continue;
    found.add('line ${_lineOf(source, arm.start)}: case${pattern.trim()}');
  }
  for (final clause in RegExp(
    r'\bon\s+(RoomFailure|NetworkFailed)\b(?:\s+catch\s*\((\w+)[^)]*\))?\s*\{',
  ).allMatches(source)) {
    final body = source.substring(
      clause.end,
      _closingBrace(source, clause.end - 1),
    );
    if (_handsItOn(body, clause.group(2))) continue;
    found.add('line ${_lineOf(source, clause.start)}: ${clause.group(0)}');
  }
  for (final tryBlock in RegExp(r'\btry\s*\{').allMatches(source)) {
    final bodyEnd = _closingBrace(source, tryBlock.end - 1);
    if (!_speaks.hasMatch(source.substring(tryBlock.end, bodyEnd))) continue;
    final clauses = source.substring(bodyEnd + 1, _clausesEnd(source, bodyEnd));
    final generic = _genericCatch.firstMatch(clauses);
    if (generic == null) continue;
    if (_namedFailure.hasMatch(clauses.substring(0, generic.start))) continue;
    found.add(
      'line ${_lineOf(source, bodyEnd)}: ${generic.group(0)!.trim()} over a line',
    );
  }
  for (final test in _typeTest.allMatches(source)) {
    found.add('line ${_lineOf(source, test.start)}: ${test.group(0)}');
  }
  for (final arm in _expressionArm.allMatches(source)) {
    found.add('line ${_lineOf(source, arm.start)}: ${arm.group(0)}');
  }
  return found;
}

void main() {
  for (final path in _doorsOfTheRoom) {
    test('12 (e): $path catches no NetworkFailed outside the reach', () {
      expect(
        _armsThatSwallowTheNetwork(_withoutComments(path)),
        isEmpty,
        reason:
            'a network failure at any door takes the room out of reach: an arm '
            'that names it, or every failure, either hands it on or tells the '
            'reach, and no type test swallows it',
      );
    });
  }

  test(
    '12 (e): the guard sees a swallowed NetworkFailed, and nothing else',
    () {
      const swallowed = '''
      switch (await _room.fetchState(id)) {
        case Answered(value: final read):
          apply(read);
        case NetworkFailed() || Refused():
          break;
      }
    ''';
      const toldToTheReach = '''
      switch (await _room.fetchState(id)) {
        case Answered(value: final read):
          apply(read);
        case NetworkFailed():
          _outOfReach(Door.watch);
        case Refused():
          break;
      }
    ''';
      const everyFailureHandedOn = '''
      switch (sent) {
        case Answered():
          land();
        case final RoomFailure failure:
          _handleRoomFailure(failure);
      }
    ''';
      const everyFailureLogged = '''
      switch (await _room.takesOf(id)) {
        case Answered(value: final listed):
          use(listed);
        case final RoomFailure failure:
          debugPrint('lost: \$failure');
          return;
      }
    ''';
      const aTypeTest = '''
      final answer = await _inbox.fetchReplies();
      if (answer is! Answered<List<HandReply>>) return;
    ''';
      const anExpressionArm = '''
      await _replace(entry, switch (answer) {
        Answered() => row,
        NetworkFailed() => row.copyWith(waits: 1),
      });
    ''';

      const aLineThatSwallowsTheNetwork = '''
      try {
        said = await _sayTheLine(LineKind.reply, () => _voice.play(url));
      } on Exception {
        said = _Said.failed;
      }
    ''';
      const aLineThatNamesTheNetworkFirst = '''
      try {
        said = await _sayTheLine(LineKind.reply, () => _voice.play(url));
      } on NetworkFailed {
        return _outOfReach(Door.reply);
      } on Exception {
        said = _Said.failed;
      }
    ''';
      const aFailureCaughtAndDropped = '''
      try {
        await _voicePanorama(turn);
      } on RoomFailure catch (failure) {
        debugPrint('\$failure');
      }
    ''';
      const aFailureCaughtAndHandedOn = '''
      try {
        await _voicePanorama(turn);
      } on RoomFailure catch (failure) {
        failed(failure);
      }
    ''';

      expect(
        _armsThatSwallowTheNetwork(aLineThatSwallowsTheNetwork),
        hasLength(1),
      );
      expect(
        _armsThatSwallowTheNetwork(aLineThatNamesTheNetworkFirst),
        isEmpty,
      );
      expect(
        _armsThatSwallowTheNetwork(aFailureCaughtAndDropped),
        hasLength(1),
      );
      expect(_armsThatSwallowTheNetwork(aFailureCaughtAndHandedOn), isEmpty);
      expect(_armsThatSwallowTheNetwork(swallowed), hasLength(1));
      expect(_armsThatSwallowTheNetwork(toldToTheReach), isEmpty);
      expect(_armsThatSwallowTheNetwork(everyFailureHandedOn), isEmpty);
      expect(_armsThatSwallowTheNetwork(everyFailureLogged), hasLength(1));
      expect(_armsThatSwallowTheNetwork(aTypeTest), hasLength(1));
      expect(_armsThatSwallowTheNetwork(anExpressionArm), hasLength(1));
    },
  );
}
