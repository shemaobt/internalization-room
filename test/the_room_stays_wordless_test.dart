import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _presentationDir = 'lib/features/sala/presentation';

// The claim code is read by the facilitator off the tablet, typed at the table — the
// room's own team never reads this screen, so the wordless rule does not reach it
// (ENG-979).
const _screensTheTeamNeverReads = {
  'lib/features/sala/presentation/widgets/codigo_view.dart',
};

const _herWordsTheTeamReads = {
  'lib/features/sala/presentation/widgets/ensaio_view.dart',
  'lib/features/sala/presentation/widgets/ensaio_final_plan_view.dart',
  'lib/features/sala/presentation/widgets/escolha_view.dart',
  'lib/features/sala/presentation/widgets/moment_label.dart',
  'lib/features/sala/presentation/widgets/scene_question.dart',
  'lib/features/sala/presentation/widgets/frase_list.dart',
  'lib/features/sala/presentation/widgets/retro_view.dart',
  'lib/features/sala/presentation/widgets/stage_heading.dart',
  'lib/features/sala/presentation/widgets/status_lines.dart',
  'lib/features/sala/presentation/widgets/scene_translate_step.dart',
};

const _wordsOnlyTheCameraReads = {
  'lib/features/sala/presentation/widgets/claquete.dart',
};

const _wordsTheTeamPicksItsLanguageBy = {
  'lib/features/sala/presentation/widgets/language_and_look.dart',
};

const _numeralsThePartsAreCalledBy = {
  'lib/features/sala/presentation/widgets/kept_retelling_buttons.dart',
};

const _wordyExceptions = {
  ..._screensTheTeamNeverReads,
  ..._herWordsTheTeamReads,
  ..._wordsOnlyTheCameraReads,
  ..._wordsTheTeamPicksItsLanguageBy,
  ..._numeralsThePartsAreCalledBy,
};

final _textWidgetPattern = RegExp(r'\bText\(');
final _commentPattern = RegExp(r'//.*$', multiLine: true);

String _sourceWithoutComments(String path) =>
    File(path).readAsStringSync().replaceAll(_commentPattern, '');

void main() {
  test('no Text( widget under presentation/ outside the named exceptions', () {
    final offenders = <String>[];

    for (final file
        in Directory(_presentationDir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      if (_wordyExceptions.contains(file.path)) continue;

      if (_textWidgetPattern.hasMatch(_sourceWithoutComments(file.path))) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'the room carries no readable words on the team\'s screens; a '
          'Text( widget outside the named exceptions puts one back: '
          '${offenders.join(', ')}',
    );
  });

  test('every named exception still exists and still needs Text(', () {
    for (final path in _wordyExceptions) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'the exception list names a file that is gone: $path',
      );
      expect(
        _textWidgetPattern.hasMatch(_sourceWithoutComments(path)),
        isTrue,
        reason:
            '$path is listed as an exception but no longer writes '
            'Text( — drop it from the list so the sweep covers it again',
      );
    }
  });
}
