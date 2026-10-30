import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';
import 'support/temp.dart';

void main() {
  group('a temp folder a test asks for is there while the test runs and gone '
      'once the test ends', () {
    late String path;

    test('while its test runs, it is there', () {
      final dir = aTempDir('sala-caso-1');
      File('${dir.path}/tomada.wav').writeAsStringSync('som');
      path = dir.path;

      expect(Directory(path).existsSync(), isTrue);
    });

    test('once its test has ended, it is gone', () {
      expect(Directory(path).existsSync(), isFalse);
    });
  });

  group('a temp folder asked for in a test\'s setUp is gone once that test '
      'ends', () {
    late Directory dir;
    late String path;

    setUp(() => dir = aTempDir('sala-caso-2'));

    test('while its test runs, it is there', () {
      File('${dir.path}/tomada.wav').writeAsStringSync('som');
      path = dir.path;

      expect(Directory(path).existsSync(), isTrue);
    });

    test('once its test has ended, it is gone', () {
      expect(Directory(path).existsSync(), isFalse);
    });
  });

  group('the harness\'s takes home lives under its file\'s temp root', () {
    late String path;

    test('while its test runs, it is under the file\'s temp root', () {
      path = SalaHarness().takesHome.path;
      File('$path/tomada.wav').writeAsStringSync('som');

      expect(p.isWithin(Directory.systemTemp.path, path), isTrue);
    });

    test('once its test has ended, it is still there for a late write', () {
      expect(Directory(path).existsSync(), isTrue);
      expect(p.isWithin(Directory.systemTemp.path, path), isTrue);
    });
  });

  group('the fake recorder\'s home is gone once its test ends', () {
    late String path;

    test('while its test runs, it is there', () {
      path = FakeRecorder().home.path;
      File('$path/tomada.wav').writeAsStringSync('som');

      expect(Directory(path).existsSync(), isTrue);
    });

    test('once its test has ended, it is gone', () {
      expect(Directory(path).existsSync(), isFalse);
    });
  });
}
