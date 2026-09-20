import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'o_aviso_nao_fecha_o_azul_test.dart' show achadoComAvisoAtivo;
import 'session_notifier_test.dart' show inConversa, settle;

/// How many times the tablet has asked the room what it is doing.
int _stateReads(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

/// How many times the room said the halt out loud.
int _haltLines(SalaHarness harness) => harness.voice.assets
    .where((asset) => asset == fixedLineAsset(needsPersonLine, testLanguage))
    .length;

/// Two beats of the watch, so that a read the room owes has certainly landed.
Future<void> _twoBeats() async => settle(const Duration(milliseconds: 300));

void main() {
  test('a mesa atendendo acaba o aviso erguido na retro', () async {
    final harness = SalaHarness();
    final container = await achadoComAvisoAtivo(harness);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().warning, isTrue);

    // Ninguém tocou no tablet: o facilitador marcou a sessão como atendida.
    harness.room.theDeskAttended();

    await waitFor('o círculo sair do verde', () => !read().warning);

    expect(
      read().needsPerson,
      isFalse,
      reason:
          'o aviso nunca prendeu a equipe, e acabar não pode prendê-la: '
          'sair dele pela porta da parada bloqueante mexeria numa voz que '
          'este aviso jamais tocou',
    );
    expect(
      _haltLines(harness),
      0,
      reason:
          'a fala E0 anuncia uma sala que parou; o aviso não para '
          'nenhuma, nem ao chegar nem ao acabar',
    );
    expect(
      read().voice,
      isNot(VoiceState.needsPerson),
      reason:
          'a equipe estava no meio da retro e nada lhe foi recusado: um '
          'aviso que acabasse pela porta da parada teria de parar a sala '
          'primeiro',
    );

    final lidas = _stateReads(harness);
    await _twoBeats();
    expect(
      _stateReads(harness),
      lidas,
      reason:
          'acabado o aviso não há mais o que vigiar: uma vigia que '
          'sobrevive ao seu motivo bate no servidor para sempre',
    );
  });

  test(
    'a mesa atendendo acaba também o aviso de um conserto recusado',
    () async {
      final harness = SalaHarness()..room.replaceCaptured = false;
      final container = await achadoComAvisoAtivo(harness);
      SalaSessionState read() => container.read(salaSessionProvider);

      expect(read().warning, isTrue);

      harness.room.theDeskAttended();

      await waitFor('o círculo sair do verde', () => !read().warning);

      expect(read().needsPerson, isFalse);
      expect(
        _haltLines(harness),
        0,
        reason:
            'a sala não fez nada do conserto e avisou; os dois ramos da '
            'resposta escrevem o mesmo aviso, e o que a mesa atende é o mesmo',
      );
    },
  );

  test(
    'a parada bloqueante lida sobre um aviso vence, e a mesa levanta as duas',
    () async {
      final harness = SalaHarness();
      final container = await achadoComAvisoAtivo(harness);
      SalaSessionState read() => container.read(salaSessionProvider);

      expect(read().warning, isTrue);

      // O mesmo par de colunas, agora dizendo a parada de verdade: o servidor
      // escreve a parada bloqueante por cima do aviso que estava lá.
      harness.room.serverHalt = HaltKind.blocking;

      await waitFor('a sala parar de vez', () => read().needsPerson);

      expect(
        read().warning,
        isFalse,
        reason:
            'a leitura que bloqueia não é a leitura que avisa: o verde '
            'sobre uma sala parada é a mentira que o círculo existe para não '
            'contar',
      );
      expect(
        _haltLines(harness),
        1,
        reason:
            'a parada que chega é uma parada como outra qualquer, e ela '
            'se anuncia uma vez',
      );

      harness.room.theDeskAttended();

      await waitFor(
        'o círculo voltar ao convite',
        () => read().voice == VoiceState.invite,
      );
      expect(read().warning, isFalse);
    },
  );

  test(
    'uma leitura que ainda diz o aviso o mantém e não chama ninguém',
    () async {
      final harness = SalaHarness();
      final container = await achadoComAvisoAtivo(harness);
      SalaSessionState read() => container.read(salaSessionProvider);
      final lidas = _stateReads(harness);
      final pedidos = harness.room.personsAsked;

      await _twoBeats();

      expect(
        _stateReads(harness),
        greaterThan(lidas),
        reason:
            'sem reler, a sala nunca saberia que a mesa atendeu: é a '
            'releitura que acaba o aviso, e ela tem de continuar enquanto ele '
            'estiver de pé',
      );
      expect(
        read().warning,
        isTrue,
        reason: 'o servidor ainda diz o aviso, e quem o apaga é a mesa',
      );
      expect(
        read().needsPerson,
        isFalse,
        reason:
            'vigiar o aviso não pode convertê-lo na parada que a regra '
            'proíbe',
      );
      expect(_haltLines(harness), 0);
      expect(
        harness.room.personsAsked,
        pedidos,
        reason:
            'quem pediu a pessoa foi a sala ao marcar o aviso; o pedido do '
            'tablet marcaria a parada como bloqueante',
      );
    },
  );

  test('a vigia do aviso sai com a passagem', () async {
    final harness = SalaHarness();
    final container = await achadoComAvisoAtivo(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().warning, isTrue);

    notifier.leaveThePassage();
    await settle();
    final lidas = _stateReads(harness);

    await _twoBeats();

    expect(
      read().warning,
      isFalse,
      reason:
          'o aviso da passagem que a equipe deixou não acende o círculo '
          'da próxima',
    );
    expect(
      _stateReads(harness),
      lidas,
      reason:
          'a vigia pergunta por uma sessão que não é mais desta sala; '
          'mantida, a resposta que acabar o aviso chega sobre o trabalho de '
          'outra passagem',
    );
  });

  test('uma leitura que falhou não acaba a vigia do aviso', () async {
    final harness = SalaHarness();
    final container = await achadoComAvisoAtivo(harness);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failStateOnceWith = const RoomUnavailable('sem rede');
    await _twoBeats();

    expect(
      read().warning,
      isTrue,
      reason:
          'uma leitura que falhou não diz nada sobre o aviso; apagá-lo '
          'aqui tiraria o verde do círculo sem que ninguém tivesse vindo',
    );
    expect(
      read().needsPerson,
      isFalse,
      reason: 'e uma leitura que falhou também não é uma parada',
    );

    harness.room.theDeskAttended();
    await waitFor('o círculo sair do verde', () => !read().warning);
  });

  test(
    'na conversa o aviso também acaba quando a mesa atende, sem mais turnos',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      SalaSessionState read() => container.read(salaSessionProvider);

      await waitFor('o aviso chegar', () => read().warning);

      // A equipe parou de falar depois do aviso: sem um turno seguinte, a cauda
      // do turno nunca mais relê o estado.
      harness.room.theDeskAttended();

      await waitFor('o círculo sair do verde', () => !read().warning);

      expect(
        read().voice,
        VoiceState.invite,
        reason: 'a sala segue de pé: o aviso acabou, e nada mais mudou',
      );
      expect(_haltLines(harness), 0);
    },
  );
}
