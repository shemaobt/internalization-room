import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

void main() {
  test('the app reads a take\'s number as ordinal', () {
    final takes = TakeView.listFrom({
      'takes': [
        {'take_id': 'g-1', 'scope': 'composed', 'ordinal': 2},
        {'take_id': 'g-2', 'scope': 'passagem-inteira'},
      ],
    });

    expect(takes[0].ordinal, 2);
    expect(takes[1].ordinal, isNull);
  });

  test('the app reads which of its part\'s recordings a take is', () {
    final takes = TakeView.listFrom({
      'takes': [
        {'take_id': 'g-1', 'scope': 'parte-2', 'ordinal': 2, 'pass_number': 3},
        {'take_id': 'g-2', 'scope': 'parte-1', 'ordinal': 1},
      ],
    });

    expect(
      takes[0].pass,
      3,
      reason:
          'é por esta conta que a sala separa a gravação que a equipe '
          'guardou da que ela abandonou',
    );
    expect(takes[1].pass, isNull);
  });
}
