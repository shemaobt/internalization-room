import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

void main() {
  test(
    'the wheel reads approved from the room\'s answer, false when absent',
    () {
      final wheel = passagensFromJson({
        'passages': [
          {'pericope': 'P01', 'audio_url': '/a', 'approved': true},
          {'pericope': 'P02', 'audio_url': '/b'},
        ],
      });

      expect(wheel.map((p) => p.approved), [true, false]);
    },
  );
}
