import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/sync_doctrine.dart';

void main() {
  test('the doctrine is vendored in the repo at the sha its pin records', () {
    final pin = readPin();

    expect(
      pin.commit,
      isNotEmpty,
      reason:
          'a regra que governa o trabalho vivia no repositório dela, e a mensagem que os '
          'guardas imprimem apontava para um documento que ninguém aqui podia abrir',
    );
    expect(
      drift(pin),
      isEmpty,
      reason:
          'um artefato vendorizado é re-sincronizado, nunca editado: divergir do pin é '
          'conflito de merge, não decisão',
    );
  });

  test(
    'a vendored artefact edited in place is reported rather than accepted',
    () {
      final dir = Directory.systemTemp.createTempSync('doctrine_pin_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final vendored = File(p.join(dir.path, vendoredDoctrine));
      vendored.parent.createSync(recursive: true);
      vendored.writeAsStringSync('dela\n');
      final pinFile = File(p.join(dir.path, 'DOCTRINE_PIN'));
      writePin('a' * 40, {vendoredDoctrine: digestOf('dela\n')}, pinFile);
      final pin = readPin(pinFile);

      expect(
        drift(pin, dir.path),
        isEmpty,
        reason: 'o pin não concordava com os bytes de que foi escrito',
      );

      vendored.writeAsStringSync('nossa agora\n');

      expect(
        drift(pin, dir.path),
        ['edited: $vendoredDoctrine'],
        reason:
            'a comparação que aceita uma edição é a que deixa setenta e sete tickets '
            'ajustarem o que é dela sem uma palavra dela',
      );
    },
  );

  test('a pin moved with no ruling beside it is refused', () {
    final dir = Directory.systemTemp.createTempSync('doctrine_rulings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final rulings = Directory(p.join(dir.path, 'rulings'))..createSync();
    File(
      p.join(rulings.path, '2026-09-03-a-doutrina-tem-dona.md'),
    ).writeAsStringSync(
      'pin: ${'c' * 40}\n'
      'word: "any change is a ruling with her word"\n'
      'written: DOCTRINE.md §5.1\n',
    );
    final recorded = readRulings(rulings.path);

    expect(
      unruled(Pin('r', 'b', 'c' * 40, const {}), recorded),
      isEmpty,
      reason:
          'um pin que a própria ruling nomeia foi chamado de não registrado',
    );

    expect(
      unruled(Pin('r', 'b', 'd' * 40, const {}), recorded),
      ['no ruling records the pin ${'d' * 12}'],
      reason:
          'um re-sync reescreve todos os shas, então só o commit pega aquele que ninguém '
          'registrou: os bytes e o registro deles andam juntos',
    );
  });

  test('every line of the acceptance bar is claimed, held here or named elsewhere', () {
    final lines = acceptanceBar();
    final record = readBarRecord();

    expect(
      lines.length,
      17,
      reason:
          'o §4 não parseia mais na barra para a qual este registro foi escrito, e o parse é '
          'o que faz uma linha nova dela chegar como build vermelho',
    );
    expect(
      barFaults(lines, record),
      isEmpty,
      reason:
          'uma linha da barra que ninguém reivindica é uma linha que ninguém está segurando',
    );

    final pendings = [
      for (final entry in record.entries)
        if (entry.value.first == pending) entry.key,
    ];
    expect(
      pendings,
      isEmpty,
      reason:
          'a última linha PENDING era "the circle is alive at `done`"; desde que o conversaTap '
          'aceita o toque em done e o teste a segura, a barra não tem mais nenhuma linha que '
          'este repositório não reivindica',
    );
  });

  test('a line she adds on the next re-sync is not silently unprotected', () {
    final record = {
      'no blessings': ['BACKEND'],
    };

    expect(barFaults(['no blessings'], record, testsExist: false), isEmpty);
    expect(
      barFaults(['no blessings', 'never "o mapa"'], record, testsExist: false),
      ['unclaimed: never "o mapa"'],
      reason:
          'um re-pin pode alargar a barra, e transcrever as linhas ao lado do registro é '
          'exatamente o que impediria de notar',
    );
  });

  test('a row naming a test that was renamed or deleted is refused', () {
    final record = {
      'The voice opens the session': [
        'test/session_notifier_test.dart::nobody kept this name',
      ],
    };

    expect(
      barFaults(['The voice opens the session'], record),
      ['no such test: test/session_notifier_test.dart::nobody kept this name'],
      reason:
          'uma linha que parece segurada e não está é pior que PENDING, e renomear teste é '
          'o que acontece toda semana neste repositório',
    );
  });

  test(
    'a fragment her rewording left behind is reported rather than ignored',
    () {
      final faults = barFaults(
        ['no blessings'],
        {
          'no ceilings on speech': ['BACKEND'],
        },
        testsExist: false,
      );

      expect(
        faults,
        ['unclaimed: no blessings', 'stale: no ceilings on speech'],
        reason:
            'casar por fragmento é o que impede um rename de ficar vermelho, e é exatamente '
            'por isso que um fragmento que não casa com nada tem de ser alto',
      );
    },
  );
}
