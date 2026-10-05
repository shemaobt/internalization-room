import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
