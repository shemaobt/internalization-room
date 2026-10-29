import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('every decision in docs/adr carries a number no other one carries', () {
    final byNumber = <String, List<String>>{};
    for (final file in Directory('docs/adr').listSync().whereType<File>()) {
      final name = p.basename(file.path);
      byNumber.putIfAbsent(name.substring(0, 4), () => []).add(name);
    }

    expect(
      {
        for (final entry in byNumber.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      },
      isEmpty,
      reason:
          'a main levou dois ADR 0140, dois 0141, dois 0146 e dois 0149, e cada '
          '«amended by» e cada «ADR 0140» passou a apontar para duas decisões',
    );
  });
}
