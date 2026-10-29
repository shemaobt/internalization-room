import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/the_suite_leaves_no_temp_folder.dart';
import 'support/temp.dart';

void main() {
  late Directory temp;
  late StringBuffer out;

  setUp(() {
    temp = aTempDir('suite-temp');
    out = StringBuffer();
  });

  Future<int> run(String script) =>
      runCountingTempFolders(['sh', '-c', script], temp, out);

  test('a run that leaves a sala folder behind fails and names it', () async {
    final code = await run('mkdir ${temp.path}/sala-deixada');

    expect(code, isNot(0));
    expect(out.toString(), contains('sala-deixada'));
  });

  test('a run that leaves the temp folder as it found it passes', () async {
    final code = await run(
      'mkdir ${temp.path}/sala-x && rm -r ${temp.path}/sala-x',
    );

    expect(code, 0);
    expect(out.toString(), isEmpty);
  });

  test(
    'a sala folder that was there before the run is not blamed on it',
    () async {
      Directory('${temp.path}/sala-antiga').createSync();

      final code = await run(
        'rm -r ${temp.path}/sala-antiga && mkdir ${temp.path}/sala-nova',
      );

      expect(code, 1);
      expect(out.toString(), contains('sala-nova'));
      expect(out.toString(), isNot(contains('sala-antiga')));
    },
  );

  test(
    'a run whose command fails fails with the command\'s own code',
    () async {
      final code = await run('exit 3');

      expect(code, 3);
    },
  );

  test('a folder that is not the suite\'s is not counted', () async {
    final code = await run('mkdir ${temp.path}/flutter_tools.abc');

    expect(code, 0);
  });
}
