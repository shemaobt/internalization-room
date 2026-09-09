import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';

void main() {
  test('every wire name the server can send resolves to a kind', () {
    const wire = {
      'missing': BtFindingKind.missing,
      'addition': BtFindingKind.addition,
      'insufficient_evidence': BtFindingKind.insufficientEvidence,
      'unclear': BtFindingKind.unclear,
    };
    wire.forEach((raw, kind) {
      expect(btFindingKindFrom(raw), kind);
    });
  });

  test('exitsByReRecording is true for addition alone', () {
    for (final kind in BtFindingKind.values) {
      expect(kind.exitsByReRecording, kind == BtFindingKind.addition,
          reason: '${kind.name} deveria ${kind == BtFindingKind.addition ? '' : 'não '}'
              'esconder a saída de recontar');
    }
  });

  test('a kind this build does not know yet degrades to null, not a crash', () {
    expect(btFindingKindFrom('algo_novo_do_servidor'), isNull);
    expect(btFindingKindFrom(null), isNull);
  });

  for (final retired in [
    'meaning_change',
    'wrong_relation',
    'reordered_event',
    'preservation_violation',
  ]) {
    test('a retired wire name, $retired, resolves to no kind', () {
      expect(btFindingKindFrom(retired), isNull);

      final verdict = BackTranslationVerdict.fromJson({
        'checked': false,
        'finding_kind': retired,
        'finding_segment_id': 'trecho-2',
        'findings_remaining': 1,
      });

      expect(verdict.findingKind, isNull);
      expect(verdict.findingSegmentId, 'trecho-2');
    });
  }

  test('a verdict with an unknown kind still enters the findings phase', () {
    final verdict = BackTranslationVerdict.fromJson(const {
      'checked': false,
      'finding_kind': 'algo_novo_do_servidor',
      'finding_segment_id': 'trecho-2',
      'findings_remaining': 1,
    });

    expect(verdict.checked, isFalse);
    expect(verdict.findingKind, isNull);
    expect(verdict.findingSegmentId, 'trecho-2');
  });
}
