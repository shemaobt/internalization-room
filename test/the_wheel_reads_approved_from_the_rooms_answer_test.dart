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

  test(
    'the wheel reads each entry\'s book and reference from the room\'s answer',
    () {
      final wheel = passagensFromJson({
        'book': 'Ruth',
        'passages': [
          {'pericope': 'panorama', 'kind': 'panorama', 'audio_url': '/p'},
          {'pericope': 'P01', 'audio_url': '/a', 'reference': 'Ruth 1:1–5'},
        ],
      });

      expect(wheel.map((p) => p.book), ['Ruth', 'Ruth']);
      expect(wheel.map((p) => p.reference), ['', 'Ruth 1:1–5']);
    },
  );
}
