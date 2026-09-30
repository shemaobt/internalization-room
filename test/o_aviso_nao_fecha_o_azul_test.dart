import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

/// Record one rehearsal part and wait for the room to have named it.
Future<void> _gravaParte(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  final partesAntes = container.read(salaSessionProvider).partes.length;
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  await waitFor('a sala nomear a parte', () {
    final partes = container.read(salaSessionProvider).partes;
    return partes.length > partesAntes && partes.last.takeId != null;
  });
}

Future<ProviderContainer> _inRetro(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await settle();
  notifier.goEnsaio();
  await _gravaParte(container, notifier);
  notifier.startRetro();
  await settle();
  return container;
}

Future<void> _traduzTrecho(
  SalaHarness harness,
  ProviderContainer container, {
  required Duration em,
}) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.playback.at = em;
  notifier.cortarTrecho();
  notifier.retroTap();
  await settle();
  await fecharACaptura(container);
  await notifier.confirmarTraducao();
  await settle();
}

/// Tell the stretch the finding points at again, the way the team does it: the azul
/// microphone lands on the translation, the circle records over, the check sends it.
Future<void> traduzirDeNovoOApontado(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  notifier.traduzirDeNovoEmPortugues();
  notifier.retroTap();
  await waitFor(
    'o microfone abrir no trecho apontado',
    () => container.read(salaSessionProvider).btPhase == BtPhase.capturing,
  );
  await fecharACaptura(container);
  await notifier.confirmarTraducao();
}

/// A sala parada num achado no segundo trecho, com o aviso de "chame uma
/// pessoa" já ativo — erguido pelo conserto de um achado anterior sobre o
/// *primeiro* trecho, que não é o que os casos que a chamam consertam: cada
/// conserto renomeia o trecho que toca, e levantar o aviso sobre o apontado
/// mudaria o nome debaixo deles.
Future<ProviderContainer> achadoComAvisoAtivo(SalaHarness harness) async {
  harness.room.verdictChecked = false;
  harness.room.verdictHasFinding = true;
  harness.room.verdictFindingPlace = 0;

  final container = await _inRetro(harness);
  final notifier = container.read(salaSessionProvider.notifier);

  await _traduzTrecho(harness, container, em: const Duration(seconds: 10));
  await waitFor(
    'o primeiro trecho chegar à sala',
    () => harness.room.chunksSent == 1,
  );
  await _traduzTrecho(harness, container, em: const Duration(seconds: 20));
  await waitFor(
    'o segundo trecho chegar à sala',
    () => harness.room.chunksSent == 2,
  );

  harness.playback.finishPlayback();
  await waitFor(
    'o clipe poder ser dado por ouvido',
    () => container.read(salaSessionProvider).canFinishBackTranslation,
  );
  await notifier.finishBackTranslation();
  await waitFor(
    'o achado apontar o primeiro trecho',
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.findings &&
        container.read(salaSessionProvider).btFindingTrecho != null,
  );

  harness.room
    ..replaceNeedsPerson = true
    ..verdictFindingPlace = 1;
  await traduzirDeNovoOApontado(container, notifier);
  // O aviso é escrito antes de o veredito ser pedido, e o pedido leva a sala ao
  // pensando: devolvê-la aí faria o gesto seguinte ser engolido por uma guarda de
  // fase e o caso passar pela razão errada.
  await waitFor(
    'a sala levantar o aviso e assentar',
    () =>
        container.read(salaSessionProvider).warning &&
        container.read(salaSessionProvider).btPhase != BtPhase.thinking,
  );
  return container;
}

/// A sala parada de vez, dentro da retro: a equipe contou um trecho e o gravador
/// não trouxe áudio nenhum do seguinte, que é a parada bloqueante desta estação.
Future<ProviderContainer> _paradaBloqueante(SalaHarness harness) async {
  final container = await _inRetro(harness);

  await _traduzTrecho(harness, container, em: const Duration(seconds: 10));
  await waitFor(
    'o primeiro trecho chegar à sala',
    () => harness.room.chunksSent == 1,
  );

  harness.recorder.returnsEmpty = true;
  await _traduzTrecho(harness, container, em: const Duration(seconds: 20));
  await waitFor(
    'a sala parar de vez',
    () => container.read(salaSessionProvider).needsPerson,
  );
  return container;
}

void main() {
  test('com o aviso ativo, o microfone azul leva à tradução e o círculo abre '
      'a captura', () async {
    final harness = SalaHarness();
    final container = await achadoComAvisoAtivo(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.traduzirDeNovoEmPortugues();
    notifier.retroTap();

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.capturing,
      reason:
          'o aviso pede uma pessoa; ele não fecha o caminho curto — só o '
          'toque longo resolve, e até lá os dois microfones continuam levando '
          'ao conserto como sempre',
    );
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'e o aviso não é uma parada: se ele prendesse a sala, este '
          'microfone abriria por engano numa sala que a mesa ainda não '
          'atendeu, e o caso acima passaria pela razão errada',
    );
  });

  test('a tradução de novo feita sob aviso chega ao servidor', () async {
    final harness = SalaHarness();
    final container = await achadoComAvisoAtivo(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final pedidosAntes = harness.room.replacesAsked.length;

    await traduzirDeNovoOApontado(container, notifier);
    await waitFor(
      'a sala sair do pensando',
      () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
    );

    expect(
      harness.room.replacesAsked.length,
      pedidosAntes + 1,
      reason:
          'o trecho traduzido de novo sob aviso ainda tem de chegar à sala como '
          'qualquer outro; o aviso não é um teto',
    );
    expect(
      container.read(salaSessionProvider).btTrechos[1].retroPath,
      harness.recorder.lastPath,
      reason: 'e o trecho apontado fica com a ponte nova',
    );
  });

  test('a parada bloqueante continua visível; o toque longo só pergunta na '
      'hora, e é a mesa quem a levanta', () async {
    final harness = SalaHarness();
    final container = await _paradaBloqueante(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().needsPerson, isTrue);
    expect(read().canResolveWithPerson, isTrue);
    final antes = harness.room.calls
        .where((call) => call == 'fetchState')
        .length;

    // O toque longo, com a sessão viva e a parada confirmada pelo servidor,
    // só pede uma releitura na hora — não derruba o aviso por si.
    notifier.resolveWithPerson();
    await waitFor(
      'a sala perguntar ao servidor na hora',
      () =>
          harness.room.calls.where((call) => call == 'fetchState').length >
          antes,
    );

    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason:
          'o servidor ainda segura a parada; soltar no toque poria a '
          'equipe de volta a falar dentro de uma sala que a mesa não '
          'atendeu',
    );

    // Quando o servidor deixa de dizer needs_person — a mesa atendeu —, a
    // sala volta sozinha ao convite, sem precisar de um novo toque.
    harness.room.theDeskAttended();
    await waitFor(
      'o círculo voltar ao convite sozinho',
      () => !read().needsPerson,
    );

    expect(
      read().needsPerson,
      isFalse,
      reason:
          'a vigia lê o estado sozinha; quem levanta a parada é a '
          'mesa, não o toque',
    );
  });

  test(
    'uma parada no meio da gravação por cima não solta o trecho armado',
    () async {
      final harness = SalaHarness();
      final container = await achadoComAvisoAtivo(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      final apontado = read().btFindingTrecho!;
      final pedidosAntes = harness.room.replacesAsked.length;
      final pedacosAntes = harness.room.chunksSent;

      notifier.traduzirDeNovoEmPortugues();
      notifier.retroTap();
      await waitFor(
        'o microfone abrir sobre a tradução emprestada',
        () => read().btPhase == BtPhase.capturing,
      );
      harness.room.serverHalt = HaltKind.blocking;
      await waitFor('a sala parar', () => read().needsPerson);
      harness.room.theDeskAttended();
      await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

      expect(
        read().btTrechoTraduzidoDeNovo?.segmentId,
        apontado.segmentId,
        reason:
            'o trecho armado só é solto por uma tradução que aterra: a parada '
            'descartou a gravação, não o conserto',
      );

      notifier.retroTap();
      await waitFor(
        'o microfone abrir de novo no mesmo trecho',
        () => read().btPhase == BtPhase.capturing,
      );
      await fecharACaptura(container);
      await notifier.confirmarTraducao();
      await waitFor(
        'a sala sair do pensando',
        () => read().btPhase != BtPhase.thinking,
      );

      expect(harness.room.replacesAsked.sublist(pedidosAntes), [
        '${apontado.segmentId}@${apontado.takeId}:'
            '${apontado.from.inMilliseconds}-${apontado.to.inMilliseconds}',
      ]);
      expect(harness.room.chunksSent, pedacosAntes);
    },
  );

  test('gravar a parte de novo também não é fechado pelo aviso', () async {
    final harness = SalaHarness();
    final container = await achadoComAvisoAtivo(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.gravarAParteDeNovo();

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason:
          'gravar a parte de novo não tem a guarda de needsPerson: o aviso '
          'pede uma pessoa e não fecha saída nenhuma da pergunta',
    );
  });
}
