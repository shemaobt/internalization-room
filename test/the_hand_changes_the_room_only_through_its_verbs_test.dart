import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _commentPattern = RegExp(r'//.*$', multiLine: true);

String _sourceWithoutComments(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

void main() {
  test('the hand changes the room only through its verbs', () {
    final source = _sourceWithoutComments(
      'lib/features/sala/data/raised_hand.dart',
    );
    final hostDeclaration = RegExp(
      r'abstract interface class HandHost \{.*?\n\}',
      dotAll: true,
    ).firstMatch(source)?.group(0);

    expect(hostDeclaration, isNotNull);
    expect(
      RegExp(r'host\.state\s*=').hasMatch(source),
      isFalse,
      reason: 'the hand writes the room through its verbs, never whole',
    );
    expect(
      source.contains('copyWith('),
      isFalse,
      reason: 'the hand never builds the session state it hands back',
    );
    expect(
      hostDeclaration!.contains('SalaSessionState'),
      isFalse,
      reason: 'the room\'s whole state is never in the hand\'s hands',
    );
  });
}
