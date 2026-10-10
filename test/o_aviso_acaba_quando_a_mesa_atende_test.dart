import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'o_aviso_nao_fecha_o_azul_test.dart' show achadoComAvisoAtivo;
import 'session_notifier_test.dart' show inConversa;

/// Beats enough for a read the room owes to have landed, at whatever cadence this
/// harness was built with: a fixed number here would be zero beats under a wider one,
/// and a "did not grow" assertion that measured nothing would read as green.
Future<void> _someBeats(SalaHarness harness) async =>
    settle(harness.settleDelay * 5);

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
      read().needsPerson,
      isFalse,
      reason:
          'a equipe estava no meio da retro e nada lhe foi recusado: um '
          'aviso que acabasse pela porta da parada teria de parar a sala '
          'primeiro',
    );

    final lidas = stateReads(harness);
    await _someBeats(harness);
    expect(
      stateReads(harness),
      lidas,
      reason:
          'acabado o aviso não há mais o que vigiar: uma vigia que '
          'sobrevive ao seu motivo bate no servidor para sempre',
    );
  });

  test(
    'a parada bloqueante lida sobre um aviso vence, e a mesa levanta as duas',
    () async {
      final harness = SalaHarness();
      final container = await achadoComAvisoAtivo(harness);
      SalaSessionState read() => container.read(salaSessionProvider);
      final pedidos = harness.room.personsAsked;

      expect(read().warning, isTrue);

      // O mesmo par de colunas, agora dizendo a parada de verdade: o servidor
      // escreve a parada bloqueante por cima do aviso que estava lá.
      harness.room.serverStatus = 'needs_person';
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
        harness.room.personsAsked,
        pedidos,
        reason:
            'a vigia leu a parada; o servidor já a tinha, e um pedido do '
            'tablet aqui apagaria um atendimento que a mesa já tivesse dado '
            '(ENG-962)',
      );

      harness.room.theDeskAttended();

      await waitFor('o círculo voltar ao convite', () => !read().needsPerson);
      expect(read().warning, isFalse);
    },
  );

  test(
    'uma leitura que ainda diz o aviso o mantém e não chama ninguém',
    () async {
      final harness = SalaHarness();
      final container = await achadoComAvisoAtivo(harness);
      SalaSessionState read() => container.read(salaSessionProvider);
      // A sala continua marcada com o aviso, que é o que ela responde a cada
      // leitura até a mesa atender.
      harness.room.serverStatus = 'needs_person';
      harness.room.serverHalt = HaltKind.warning;
      final lidas = stateReads(harness);
      final pedidos = harness.room.personsAsked;

      await _someBeats(harness);

      expect(
        stateReads(harness),
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
    final lidas = stateReads(harness);

    await _someBeats(harness);

    expect(
      stateReads(harness),
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

    harness.room.failStateOnceWith = const NetworkFailed('sem rede');
    await _someBeats(harness);

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
    },
  );

  test(
    'a parada bloqueante que a leitura troca por um aviso deixa o aviso vigiado',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.blocking;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      SalaSessionState read() => container.read(salaSessionProvider);

      await waitFor('a sala parar de vez', () => read().needsPerson);

      // O pedido do tablet não chegou, então a sala continua marcada com o
      // aviso que o orçamento levantou: a leitura seguinte devolve a equipe,
      // mas a sessão continua pedindo alguém.
      harness.room.serverHalt = HaltKind.warning;

      await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

      expect(
        read().warning,
        isTrue,
        reason:
            'a leitura que devolveu a equipe ainda diz o aviso, e o aviso é '
            'o que sobra da parada: apagá-lo aqui esconderia da equipe que a '
            'sala continua pedindo alguém',
      );

      harness.room.theDeskAttended();

      await waitFor('o círculo sair do verde', () => !read().warning);
    },
  );

  test('a rede que cai e volta devolve o aviso vigiado', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('o aviso chegar', () => read().warning);

    harness.room.reachable = false;
    await waitFor('a sala cair', () => read().offline);
    harness.room.reachable = true;
    await waitFor('a sala voltar', () => !read().offline);

    // A equipe não toca em nada depois da volta: sem a vigia, nada mais nesta
    // estação relê o estado.
    harness.room.theDeskAttended();

    await waitFor('o círculo sair do verde', () => !read().warning);
  });

  test('o toque longo numa sala fora não larga a vigia do aviso', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('o aviso chegar', () => read().warning);

    harness.network.reachable = false;
    harness.room.reachable = false;
    await waitFor('a sala cair', () => read().offline);

    // Fora, o toque longo é a tentativa de voltar e continua a ser a saída
    // local que sempre foi — mas a sessão continua marcada com o aviso.
    notifier.resolveWithPerson();
    await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

    expect(
      read().warning,
      isTrue,
      reason:
          'o toque não é a mesa: soltar a sala não apaga um aviso que '
          'ninguém veio olhar',
    );

    harness.network.reachable = true;
    harness.room.reachable = true;
    harness.room.theDeskAttended();

    await waitFor('o círculo sair do verde', () => !read().warning);
  });
}
