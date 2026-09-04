import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a faixa mínima declarada nunca fica abaixo do que o lock exige', () {
    final pubspecYaml = File('pubspec.yaml').readAsStringSync();
    final pubspecLock = File('pubspec.lock').readAsStringSync();

    final declaredMatch = RegExp(
      r'sdk:\s*\^(\d+)\.(\d+)\.(\d+)',
    ).firstMatch(pubspecYaml);
    final lockMatch = RegExp(
      r'dart:\s*">=(\d+)\.(\d+)\.(\d+)',
    ).firstMatch(pubspecLock);

    expect(
      declaredMatch,
      isNotNull,
      reason: 'pubspec.yaml deveria declarar environment.sdk como ^x.y.z',
    );
    expect(
      lockMatch,
      isNotNull,
      reason: 'pubspec.lock deveria trazer sdks.dart como ">=x.y.z <4.0.0"',
    );

    final declared = List.generate(
      3,
      (i) => int.parse(declaredMatch!.group(i + 1)!),
    );
    final lock = List.generate(3, (i) => int.parse(lockMatch!.group(i + 1)!));

    final declaredBelowLock =
        declared[0] < lock[0] ||
        (declared[0] == lock[0] && declared[1] < lock[1]) ||
        (declared[0] == lock[0] &&
            declared[1] == lock[1] &&
            declared[2] < lock[2]);

    expect(
      declaredBelowLock,
      isFalse,
      reason:
          'um dev na SDK declarada não satisfaz o lock resolvido; '
          '`pub get` re-resolve em silêncio e rebaixa pacotes do lock — '
          'declarado ${declared.join(".")}, lock exige ${lock.join(".")}',
    );
  });
}
