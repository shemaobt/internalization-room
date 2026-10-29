import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

void main() {
  test('a part recorded for scene 3 after scene 1 is numbered 3, not its '
      'place in the row', () {
    final state = SalaSessionState(
      keptTakes: [
        KeptTake(scopeId: KeptScope.parte(3), path: '/p3.m4a'),
        KeptTake(scopeId: KeptScope.parte(1), path: '/p1.m4a'),
      ],
    );

    expect(state.numeroDaParte(0), 1);
    expect(
      state.numeroDaParte(1),
      3,
      reason: 'a parte da cena 3 se dizia 2, o lugar dela na fileira',
    );
    expect(
      state.numeroDaParte(2),
      3,
      reason: 'um lugar que a fileira não tem ainda se conta pelo lugar',
    );
  });
}
