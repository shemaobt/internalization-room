import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle, withDiskThatAnswersAtOnce;

void main() {
  test('a book with nothing left to offer reaches a person', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.naRoda, isEmpty);
    expect(state.needsPerson, isTrue);
    expect(
      state.livroInteiroFeito,
      isTrue,
      reason: 'o servidor mesmo não devolveu nenhuma passagem',
    );
    expect(
      harness.room.deviceAsksReceived,
      isNotEmpty,
      reason: 'a sala de fato chama alguém, não só acende needsPerson',
    );
    expect(
      harness.voice.fixedLines,
      isNot(contains(('E0', testLanguage))),
      reason: 'o círculo parado já é o aviso; o app não fala por cima dele',
    );
  });

  test('a long press reloads the wheel, and lets the team through once it has '
      'something', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    harness.room.passages = const [
      Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
    ];
    notifier.resolveWithPerson();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(
      state.needsPerson,
      isFalse,
      reason: 'a escolha foi reaberta de fora, e o servidor tinha mudado',
    );
    expect(
      state.oferecida?.pericope,
      'P01',
      reason: 'a roda recarregada de fato oferece a passagem nova',
    );
  });

  test('a long press over a book still genuinely empty halts again', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.resolveWithPerson();
    await settle();

    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason:
          'a visita reaberta perguntou o servidor de novo, e ele continua '
          'sem nada; fingir que o long press resolveu escondia isso',
    );
  });

  test('the room is thinking while the clip is still coming down', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.holdNextFetch();
    unawaited(notifier.abrirEscolha());
    await waitFor(
      'a primeira fala ser buscada',
      () => harness.voice.fetched.isNotEmpty,
    );

    expect(container.read(salaSessionProvider).voice, VoiceState.thinking);

    harness.voice.finishHeldFetch();
    await settle();
    expect(harness.voice.played, isNotEmpty);
  });

  test('the panorama is offered once per book, not once per opening', () async {
    final harness = SalaHarness();
    final first = harness.container();
    addTearDown(first.dispose);

    await first.read(salaSessionProvider.notifier).openTheRoom();
    await settle();
    expect(first.read(salaSessionProvider).stage, SalaStage.convite);

    await first.read(salaSessionProvider.notifier).openConvite();
    await waitFor(
      'o livro ser dado por aberto',
      () => harness.finished.done.any((it) => it.startsWith('livro:')),
    );

    final second = harness.container();
    addTearDown(second.dispose);
    await second.read(salaSessionProvider.notifier).openTheRoom();
    await settle();

    expect(second.read(salaSessionProvider).stage, SalaStage.escolha);
  });

  test('leaving a passage goes back to the wheel and keeps it there', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);

    notifier.leaveThePassage();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.escolha);
    expect(state.naRoda, hasLength(3));
    expect(harness.finished.done, isEmpty);
  });

  test(
    'a passage the room refuses sends the team back to the wheel, not to a person',
    () async {
      final harness = SalaHarness()..room.passagesThatCannotOpen = {'P01'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.escolha,
        reason:
            'o 400 da criação é a passagem que não abre, e a resposta a ele é a '
            'roda',
      );
      expect(state.needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(
        harness.voice.fixedLines,
        isNot(contains(('E0', testLanguage))),
        reason:
            'a sala pedia uma pessoa para uma passagem que pessoa nenhuma abre no '
            'tablet',
      );
    },
  );

  test(
    'three passages that all cannot open call a person, each hitting the door once',
    () async {
      final harness = SalaHarness()
        ..room.passagesThatCannotOpen = {'P01', 'P02', 'P03'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      for (var attempt = 0; attempt < 3; attempt++) {
        notifier.entrarNaOferecida();
        await settle();
      }

      final state = container.read(salaSessionProvider);
      expect(
        harness.room.calls.where((call) => call == 'createSession'),
        hasLength(3),
        reason: 'cada toque na roda tem de bater na porta de novo',
      );
      expect(
        state.needsPerson,
        isTrue,
        reason:
            'todas as passagens da roda foram recusadas nesta visita à '
            'escolha, e isso é o mesmo que a roda não ter nada a oferecer',
      );
      expect(harness.room.personsAsked, 0);
      expect(
        harness.room.deviceAsksReceived,
        isNotEmpty,
        reason: 'a sala de fato chama alguém, não só acende needsPerson',
      );
      expect(
        harness.voice.fixedLines,
        isNot(contains(('E0', testLanguage))),
        reason:
            'a sala chama uma pessoa pelo mesmo caminho de um livro sem nada '
            'a oferecer, sem uma fala fixa nova',
      );
      expect(
        state.livroInteiroFeito,
        isFalse,
        reason:
            'as passagens saíram da roda por recusa nesta visita, e não '
            'porque o time as trabalhou; a próxima visita as devolve',
      );
    },
  );

  test(
    'lifting the halt every passage refused raised offers them again',
    () async {
      final harness = SalaHarness()
        ..room.passagesThatCannotOpen = {'P01', 'P02', 'P03'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      for (var attempt = 0; attempt < 3; attempt++) {
        notifier.entrarNaOferecida();
        await settle();
      }
      expect(container.read(salaSessionProvider).needsPerson, isTrue);

      harness.room.passagesThatCannotOpen = {};
      notifier.resolveWithPerson();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.needsPerson,
        isFalse,
        reason: 'a pessoa levantou o halt; a escolha volta a responder',
      );
      expect(
        state.stage,
        SalaStage.escolha,
        reason: 'a roda foi recarregada, não deixada morta onde parou',
      );
      expect(
        state.oferecida?.pericope,
        'P01',
        reason:
            'levantar o halt na escolha é uma visita nova: a memória de '
            'recusa some e o servidor é perguntado de novo',
      );
    },
  );

  test(
    'the increase from a passage before a refused one lands past it',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      harness.room.passagesThatCannotOpen = {'P02'};
      notifier.apontarPassagem(1);
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
      expect(
        container.read(salaSessionProvider).oferecida?.pericope,
        'P01',
        reason: 'a roda recarregou e parou na primeira ofertável',
      );

      // O incremento que a régua faz a cada passo mira em P01+1, e P02
      // (o índice mirado) foi recusado nesta visita: o passo tem de
      // continuar até P03, não travar em P02.
      notifier.apontarPassagem(1);
      await settle();

      expect(
        container.read(salaSessionProvider).oferecida?.pericope,
        'P03',
        reason:
            'o incremento de VoiceOver mira P01+1 (P02, recusado); parado no '
            'meio do nada, ele não move o dedo — o passo tem de terminar em '
            'P03',
      );
    },
  );

  test(
    'a passage refused at creation is not offered again in the same visit to the Choice',
    () async {
      final harness = SalaHarness()
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
          Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
        ]
        ..room.passagesThatCannotOpen = {'P01', 'P02'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();

      var state = container.read(salaSessionProvider);
      expect(
        state.naRoda?.map((passagem) => passagem.pericope),
        containsAll(['P01', 'P02']),
        reason: 'a roda continua sendo a lista do servidor',
      );
      expect(
        state.oferecida?.pericope,
        isNot('P01'),
        reason: 'a passagem recusada não é a que a roda oferece agora',
      );
      notifier.apontarPassagem(0);
      await settle();
      expect(
        container.read(salaSessionProvider).oferecida?.pericope,
        isNot('P01'),
        reason: 'o dedo não pousa numa passagem recusada nesta visita',
      );
      expect(state.needsPerson, isFalse);

      notifier.entrarNaOferecida();
      await settle();

      state = container.read(salaSessionProvider);
      expect(
        harness.room.calls.where((call) => call == 'createSession'),
        hasLength(2),
      );
      expect(state.needsPerson, isTrue);
      expect(
        state.naRoda?.map((passagem) => passagem.pericope),
        containsAll(['P01', 'P02']),
        reason: 'a roda do servidor continua a mesma; só a oferta acabou',
      );
      expect(harness.room.personsAsked, 0);
    },
  );

  test(
    'a refused passage is offered again on the next visit to the Choice',
    () async {
      final harness = SalaHarness()..room.passagesThatCannotOpen = {'P01'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      expect(
        container.read(salaSessionProvider).oferecida?.pericope,
        isNot('P01'),
      );

      // A visita muda de verdade: entra numa passagem que abre e sai dela, em
      // vez de reabrir a escolha na mão.
      notifier.entrarNaOferecida();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      notifier.leaveThePassage();
      await settle();

      notifier.apontarPassagem(0);
      await settle();
      expect(
        container.read(salaSessionProvider).oferecida?.pericope,
        'P01',
        reason: 'a escolha foi reaberta de fora, e o servidor pode ter mudado',
      );
    },
  );

  test(
    'a network return in the middle of the same visit keeps a refusal',
    () async {
      final harness = SalaHarness()..room.passagesThatCannotOpen = {'P01'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);

      // A rede cai no meio desta mesma visita à escolha — sem sair dela — e
      // depois volta.
      harness.room.reachable = false;
      await notifier.abrirEscolha();
      await settle();
      expect(container.read(salaSessionProvider).offline, isTrue);

      harness.room.reachable = true;
      notifier.retryNow();
      await settle();
      expect(container.read(salaSessionProvider).offline, isFalse);

      notifier.apontarPassagem(0);
      await settle();
      expect(
        container.read(salaSessionProvider).oferecida?.pericope,
        isNot('P01'),
        reason:
            'a rede voltou sem que ninguém saísse da escolha; a mesma visita '
            'continua, e a recusa continua valendo',
      );
    },
  );

  test(
    'entering a passage for real between two refusals forgets the first one',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      // P02 é aberto e deixado de lado, para existir uma sessão a retomar.
      notifier.apontarPassagem(1);
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      notifier.leaveThePassage();
      await settle();
      expect(await harness.emAberto.of('Ruth', 'P02'), isNotNull);

      // P01 é recusado nesta mesma visita.
      harness.room.passagesThatCannotOpen = {'P01'};
      notifier.apontarPassagem(0);
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
      harness.room.passagesThatCannotOpen = {};

      // P02 é retomado de verdade; a sessão lembrada sumiu no meio da
      // retomada, e a nova tentativa também é recusada.
      harness.room.failHeldTurnWith = const SessionGone();
      harness.room.passagesThatCannotOpen = {'P02'};
      notifier.apontarPassagem(1);
      await settle();
      notifier.entrarNaOferecida();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.escolha);
      expect(
        state.oferecida?.pericope,
        'P01',
        reason:
            'P02 abriu de verdade entre a recusa de P01 e agora; a visita '
            'anterior acabou ali, e a memória da recusa não atravessa',
      );
    },
  );

  test(
    'a remembered session gone and a fresh one refused send the team back to the wheel',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      notifier.leaveThePassage();
      await settle();
      expect(await harness.emAberto.of('Ruth', 'P01'), isNotNull);

      harness.room.failHeldTurnWith = const SessionGone();
      harness.room.passagesThatCannotOpen = {'P01'};
      notifier.entrarNaOferecida();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.escolha);
      expect(state.needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(
        await harness.emAberto.of('Ruth', 'P01'),
        isNull,
        reason: 'a sessão lembrada sumiu, então não há onde retomar',
      );
    },
  );

  test(
    'a creation refused beside a row kept in another language leaves that row alone',
    () async {
      final harness = SalaHarness()..room.passagesThatCannotOpen = {'P01'};
      const noutraLingua = ResumePoint(
        sessionId: 'sessao-em-ingles',
        stage: SalaStage.conversa,
        language: 'en',
      );
      harness.emAberto.rows['Ruth/P01'] = noutraLingua;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.escolha);
      expect(state.needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(
        await harness.emAberto.of('Ruth', 'P01'),
        same(noutraLingua),
        reason:
            'o 400 não distingue língua desconhecida de passagem que não anda, e '
            'a sessão da outra língua pode estar viva',
      );
    },
  );

  test(
    'a panorama the room refuses at the door sends the team to the wheel, not to a person',
    () async {
      final harness = SalaHarness()
        ..room.passagesThatCannotOpen = {panoramaPericope};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openTheRoom();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.convite);
      await notifier.openConvite();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.escolha);
      expect(state.needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(harness.voice.fixedLines, isNot(contains(('E0', testLanguage))));
    },
  );

  test(
    'three panorama spokes refused at the door never spend a strike on the room',
    () async {
      final harness = SalaHarness()
        ..room.passages = const [
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ]
        ..room.passagesThatCannotOpen = {panoramaPericope};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      for (var attempt = 0; attempt < 3; attempt++) {
        notifier.entrarNaOferecida();
        await settle();
      }

      final state = container.read(salaSessionProvider);
      expect(
        harness.room.calls.where((call) => call == 'createSession'),
        hasLength(3),
      );
      expect(
        state.needsPerson,
        isFalse,
        reason:
            'na roda nada apaga a escada, e cada recusa contada levava a '
            'terceira a chamar alguém',
      );
      expect(harness.room.personsAsked, 0);
    },
  );

  test(
    'a refusal anywhere else stops for a person, never for a network that is fine',
    () async {
      final harness = SalaHarness()
        ..room.failWith = const Refused('UNAUTHORIZED');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.offline,
        isFalse,
        reason:
            'a recusa caía no último ramo do funil e a sala dizia, numa rede boa, '
            'que a internet tinha ido embora',
      );
      expect(state.needsPerson, isTrue);
    },
  );

  test(
    'a session erased mid conversation returns to the wheel, not to a person',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();

      harness.room.failHeldTurnWith = const SessionGone();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.escolha,
        reason:
            'a sessão sumiu no meio da conversa; a equipe volta para escolher de novo, '
            'como o cliente dela faz num 404 — sem ficar parada esperando alguém',
      );
      expect(state.needsPerson, isFalse);
      expect(
        harness.room.personsAsked,
        0,
        reason:
            'nenhuma entrada nasce na fila da mesa para uma sessão que o servidor já '
            'esqueceu',
      );
      expect(
        state.naRoda?.map((p) => p.pericope),
        contains('P01'),
        reason: 'a passagem continua oferecida na roda',
      );
    },
  );

  test('a take that finishes playing stops its own pulse', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.playTheRehearsal();
    await settle();
    expect(container.read(salaSessionProvider).playPing, isTrue);

    harness.playback.finishPlayback();
    await settle();

    expect(container.read(salaSessionProvider).playPing, isFalse);
  });

  test('the circle does not record over the facilitator answering', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/voice/r1')],
    );
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await waitFor(
      'uma resposta chegar sem ser ouvida',
      () => container.read(salaSessionProvider).hasUnheardReply,
    );
    harness.voice.holdNextLine();
    notifier.handTap();
    await waitFor(
      'uma resposta começar a tocar',
      () => container.read(salaSessionProvider).playingReplyId != null,
    );

    final before = harness.recorder.captures;
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.captures, before);
    harness.voice.finishHeldLine();
  });

  test(
    'a question sent to a person is answered by silence, not a spoken line',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.handTap();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'a pergunta ser enviada à mão',
        () => harness.inbox.questionsSent.isNotEmpty,
      );
      await settle();

      expect(
        harness.voice.assets,
        isEmpty,
        reason: 'o Guia não anuncia a pergunta nem a resposta — o envio é mudo',
      );
      expect(harness.voice.fixedLines, isEmpty);
      expect(
        container.read(salaSessionProvider).questionPending,
        isTrue,
        reason: 'o ponto na mão é que carrega a espera agora, não uma fala',
      );
    },
  );

  test(
    'a second question right after the first is still met with silence',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      for (var asked = 0; asked < 2; asked++) {
        notifier.handTap();
        notifier.conversaTap();
        await settle();
        notifier.conversaTap();
        await waitFor(
          'mais uma pergunta ser enviada à mão',
          () => harness.inbox.questionsSent.length > asked,
        );
        await settle();
      }

      expect(
        harness.voice.assets,
        isEmpty,
        reason:
            'nem a primeira pergunta nem a segunda tiram o Guia do silêncio',
      );
      expect(harness.voice.fixedLines, isEmpty);
    },
  );

  test('a stretch the room did not capture is still kept as audio', () async {
    final harness = SalaHarness();
    harness.room.chunkCaptured = false;
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'a retro começar a tocar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
    );
    await settle();

    var queued = await harness.takes.entries();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (queued.where((entry) => entry.kind == 'retro').isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      queued = await harness.takes.entries();
    }
    expect(
      queued.where((entry) => entry.kind == 'retro'),
      isNotEmpty,
      reason:
          'o servidor devolve 200 sem guardar nada; se o app também soltar, o trecho deixa de existir',
    );
  });

  test('leaving a passage does not strand the take on disk', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    final recorded = harness.recorder.lastPath;
    expect(recorded, isNotNull);

    notifier.leaveThePassage();
    await settle();

    expect(harness.recorder.deleted, contains(recorded));
  });

  test('a stretch that failed keeps its own place in the row', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.room.chunkCaptured = false;
    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'um trecho da retro falhar',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
    );

    harness.room.chunkCaptured = true;
    harness.playback.at = const Duration(seconds: 30);
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'um trecho da retro passar',
      () => container.read(salaSessionProvider).btTrechos.isNotEmpty,
    );

    final state = container.read(salaSessionProvider);
    expect(
      state.btChunkFailures,
      [1],
      reason:
          'o trecho que falhou foi o primeiro, e é a primeira conta que fica oca',
    );
    expect(state.btTrechos, hasLength(1));
    expect(
      state.btTrechos.length + state.btChunkFailures.length,
      2,
      reason: 'uma conta por trecho contado — nem a mais, nem a menos',
    );
  });

  test(
    'a recording written off for a missing file is spoken about too',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);

      final entry = await harness.takes.enqueue(
        harness.recorder.aFile('sumida'),
        sessionId: 'sessao-de-ontem',
        kind: 'ensaio',
        scope: 'inteira',
      );
      File(entry.path).deleteSync();
      await harness.takes.flush();

      await container.read(salaSessionProvider.notifier).refreshUnsent();
      await settle();

      expect(
        harness.voice.assets,
        contains(strandedTakeAsset(testLanguage)),
        reason:
            'dar uma gravação por perdida em silêncio é perdê-la duas vezes',
      );
    },
  );

  test(
    'a recording written off with its audio still there is not called stranded',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);

      final entry = await harness.takes.enqueue(
        harness.recorder.aFile('condenada'),
        sessionId: 'sessao-de-ontem',
        kind: 'ensaio',
        scope: 'inteira',
      );
      final audio = File(entry.path);
      final gravado = audio.readAsBytesSync();
      audio.deleteSync();
      await harness.takes.flush();
      // O áudio está de volta — é o tablet de campo, onde ele nunca chegou a sair.
      audio.writeAsBytesSync(gravado);

      // A conta corre ANTES do flush que vai recuperar a linha: é essa ordem, em
      // session_notifier, que decide se a sala fala.
      await container.read(salaSessionProvider.notifier).refreshUnsent();
      await settle();

      expect(
        harness.voice.assets,
        isNot(contains(strandedTakeAsset(testLanguage))),
        reason:
            'a linha encalhada existe para dizer que uma gravação não vai subir; '
            'dizê-la de uma que sobe no flush seguinte é dar um susto falso à equipe '
            'justamente nos aparelhos que este conserto veio resgatar',
      );
    },
  );

  test('a stranded recording is spoken before any session exists', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await harness.takes.enqueue(
      harness.recorder.aFile('perdida'),
      sessionId: 'sessao-de-ontem',
      kind: 'ensaio',
      scope: 'inteira',
    );
    harness.room.reachable = false;
    for (var wait = 0; wait <= takeUploadWaitsBeforeSaying; wait++) {
      await harness.takes.flush();
    }

    await container.read(salaSessionProvider.notifier).refreshUnsent();
    await settle();

    expect(container.read(salaSessionProvider).sessionId, isNull);
    expect(harness.voice.assets, contains(strandedTakeAsset(testLanguage)));
  });

  test(
    'a name already on its way does not speak over where the finger went',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      harness.voice.played.clear();

      harness.voice.holdNextFetch();
      notifier.dizerAPassagem();
      await waitFor(
        'uma segunda fala ser buscada',
        () => harness.voice.fetched.length > 1,
      );

      notifier.apontarPassagem(2);
      harness.voice.finishHeldFetch();
      await settle();

      expect(
        harness.voice.played,
        isEmpty,
        reason:
            'a fala em curso era da P01; o dedo já estava na P03 quando ela chegou',
      );
      expect(container.read(salaSessionProvider).oferecida?.pericope, 'P03');
      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.invite,
        reason:
            'e não pode deixar a tela travada em "falando" sobre a passagem errada',
      );
    },
  );

  test('a rehearsal that will not play never opens the terminei', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.failPlayback();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(
      state.btClipEnded,
      isFalse,
      reason:
          'uma falha chegava como conclusão, e é a conclusão que abre o terminei',
    );
    expect(state.canFinishBackTranslation, isFalse);
  });

  test(
    'a retro with no rehearsal reaches a person, not the terminei',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      notifier.startRetro();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.btClipEnded,
        isFalse,
        reason: 'não haver ensaio nenhum não é um ensaio que chegou ao fim',
      );
      expect(state.needsPerson, isTrue);
    },
  );

  test(
    'a rehearsal play that fails gives the ensaio back its gestures',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await settle();
      notifier.takeKeep();
      await settle();
      notifier.playTheRehearsal();
      await settle();
      expect(container.read(salaSessionProvider).playPing, isTrue);

      harness.playback.failPlayback();
      await settle();

      expect(
        container.read(salaSessionProvider).playPing,
        isFalse,
        reason:
            'preso tocando, o toque no círculo não faz nada e o play não '
            'desenha o glifo de tocar — a tela move e não responde',
      );
      notifier.ensaioTap();
      expect(
        container.read(salaSessionProvider).ensaio,
        EnsaioStatus.recording,
        reason: 'a falha deixa a sala em silêncio, e gravar volta a funcionar',
      );
    },
  );

  test('a reply that will not play stays unheard and calls nobody', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/voice/r1')],
    );
    harness.voice.succeeds = false;
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await waitFor(
      'uma resposta chegar sem ser ouvida',
      () => container.read(salaSessionProvider).hasUnheardReply,
    );
    notifier.handTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(
      state.hasUnheardReply,
      isTrue,
      reason:
          'uma resposta que ninguém ouviu era dada como ouvida só porque o '
          'player falhou, e a facilitadora via "ouvida" na mesa',
    );
    expect(state.playingReplyId, isNull);
    expect(
      state.needsPerson,
      isFalse,
      reason:
          'a resposta não tocou, mas a conversa segue rodando — chamar uma pessoa '
          'para isso é mais do que o próprio pedido da mão faz num fetch que falha',
    );
    expect(
      harness.inbox.heard,
      isEmpty,
      reason: 'o servidor não pode carimbar o que a equipe não ouviu',
    );
  });

  test(
    'a halt read from the server status is not announced by the app',
    () async {
      final harness = SalaHarness(
        settleDelay: const Duration(milliseconds: 30),
      );
      harness.room.serverStatus = 'needs_person';
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);

      await waitFor(
        'a sala pedir uma pessoa',
        () => container.read(salaSessionProvider).needsPerson,
      );

      expect(
        harness.voice.fixedLines,
        isNot(contains(('E0', testLanguage))),
        reason:
            'a leitura de estado não é um turno; quem fala E0 é o servidor, '
            'no turno em que ele decidir, não a vigia que só leu a marca',
      );
    },
  );

  test('a session the room forgot does not keep being told about it', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    final asked = harness.room.personsAsked;

    harness.room.failHeldTurnWith = const SessionGone();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.sessionId, isNull);
    expect(state.needsPerson, isFalse);
    expect(harness.voice.fixedLines, isNot(contains(('E0', testLanguage))));
    expect(
      harness.room.personsAsked,
      asked,
      reason:
          'uma sessão que o servidor já esqueceu nunca chega a ser avisada — a '
          'equipe volta para a roda em silêncio em vez de esperar alguém',
    );
  });

  test(
    'a wheel that keeps failing to load still climbs its own ladder, retry after retry',
    () async {
      final harness = SalaHarness()
        ..room.failWith = const Refused('BAD_REQUEST');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.escolhaTap();
      await settle();
      notifier.escolhaTap();
      await settle();

      expect(
        container.read(salaSessionProvider).needsPerson,
        isTrue,
        reason:
            'o toque que refaz a tentativa de carregar a roda zerava '
            '_roomFailures a cada vez, e três tentativas seguidas do mesmo '
            'carregamento quebrado nunca batiam o limiar que chama alguém',
      );
    },
  );

  test('no network and no room wear different faces', () async {
    final harness = SalaHarness()..network.radioSeesNothing = true;
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    await settle();

    expect(container.read(salaSessionProvider).reach, RoomReach.noNetwork);

    final semSala = SalaHarness()..network.reachable = false;
    final outro = semSala.container();
    addTearDown(outro.dispose);
    await outro.read(salaSessionProvider.notifier).goConversa();
    await settle();

    expect(
      outro.read(salaSessionProvider).reach,
      RoomReach.roomSilent,
      reason:
          'endereço errado numa rede perfeita foi o que travou o aparelho hoje, e '
          'a sala disse que a internet tinha caído',
    );
  });

  test(
    'a kept take still reaches the queue when the room is disposed',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await settle();
      notifier.takeKeep();
      container.dispose();
      await settle(const Duration(milliseconds: 400));

      expect(
        await harness.takes.entries(),
        isNotEmpty,
        reason:
            'a guarda contra ler providers descartados foi posta antes do '
            'enfileiramento, no método cujo trabalho é não perder gravação',
      );
    },
  );

  test('the hand does not bury the way back from an outage', () async {
    // No pending reply on purpose: with one, the hand plays it and never reaches the
    // branch that overwrites the offline state.
    final harness = SalaHarness(
      retryBackoff: const [Duration(milliseconds: 30)],
    );
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.network.reachable = false;
    harness.room.reachable = false;
    harness.inbox.refuses = true;
    notifier.handTap();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor(
      'a sala se dar por fora do ar',
      () => container.read(salaSessionProvider).offline,
    );

    notifier.handTap();
    await settle();

    expect(
      container.read(salaSessionProvider).offline,
      isTrue,
      reason:
          'a mão escrevia needsPerson por cima de offline, e uma queda de rede '
          'virava uma parada à espera de uma pessoa',
    );

    harness.network.reachable = true;
    harness.room.reachable = true;
    await waitFor(
      'a sala voltar ao ar',
      () => !container.read(salaSessionProvider).offline,
      limit: const Duration(seconds: 3),
    );
    expect(
      container.read(salaSessionProvider).offline,
      isFalse,
      reason: 'e a queda voltava a se curar sozinha',
    );
  });

  test(
    'a settle that finds the session gone returns to the wheel instead of halting',
    () async {
      final harness = SalaHarness(
        settleDelay: const Duration(milliseconds: 40),
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      // The poll is armed at the end of the opening turn and fires once, on the
      // settleDelay above (40 ms). Setting the failure here, right after the opening
      // turn's own work has had a moment to finish but well under that delay, catches
      // that one poll, which is the only thing that reads the session between turns.
      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle(const Duration(milliseconds: 5));
      harness.room.failStateOnceWith = const SessionGone();
      await waitFor(
        'a sala voltar para a roda',
        () => container.read(salaSessionProvider).stage == SalaStage.escolha,
        limit: const Duration(seconds: 3),
      );

      final state = container.read(salaSessionProvider);
      expect(
        state.needsPerson,
        isFalse,
        reason:
            'o 404 do settle caía no mesmo funil de um turno; a equipe volta para a '
            'roda em silêncio em vez de ficar parada esperando alguém',
      );
    },
  );

  test('a denied microphone leaves no screen pretending to record', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    harness.recorder.permitted = false;
    notifier.ensaioTap();
    await settle();

    expect(
      container.read(salaSessionProvider).ensaio,
      EnsaioStatus.idle,
      reason:
          'a porteira troca a tela, mas o estado embaixo dela é o que a equipe '
          'encontra ao voltar — e ele dizia que a sala estava gravando',
    );
  });

  test(
    'a turn the recorder never handed back returns to the invite in silence',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.conversaTap();
      await settle();
      harness.recorder.returnsNothing = true;
      notifier.conversaTap();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.needsPerson,
        isFalse,
        reason:
            'a equipe acabou de falar a passagem inteira e nada voltou do gravador; '
            'voltar ao convite em silêncio é o mesmo descarte que o ensaio tinha, sem '
            'chamar ninguém',
      );
      expect(state.voice, VoiceState.invite);
    },
  );

  test(
    'a turn recorded into nothing returns to the invite instead of going up',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.conversaTap();
      await settle();
      final subiram = harness.room.turnsSent;
      harness.recorder.returnsEmpty = true;
      notifier.conversaTap();
      await settle();

      expect(
        harness.room.turnsSent,
        subiram,
        reason:
            'o arquivo de zero byte subia como turno e a sala respondia a um '
            'silêncio que a equipe nunca disse',
      );
      expect(
        container.read(salaSessionProvider).needsPerson,
        isFalse,
        reason:
            'gravador que devolve arquivo sem um byte volta ao convite em silêncio, '
            'como o descarte silencioso do capture guard dela',
      );
    },
  );

  test(
    'a calibration capture the recorder never handed back returns to the invite',
    () async {
      final harness = SalaHarness()..room.bridgeMode = 'calibration_pending';
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      await settle();
      expect(
        container.read(salaSessionProvider).conviteStep,
        ConviteStep.entrada,
      );

      harness.recorder.returnsNothing = true;
      notifier.conviteTap();
      await settle();
      notifier.conviteTap();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.needsPerson,
        isFalse,
        reason:
            'a calibração vazia volta ao convite em silêncio, como qualquer outra '
            'captura vazia',
      );
      expect(state.voice, VoiceState.invite);
    },
  );

  test(
    'a question the recorder never handed back returns to the invite in silence',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.handTap();
      notifier.conversaTap();
      await settle();
      harness.recorder.returnsNothing = true;
      notifier.conversaTap();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.needsPerson, isFalse);
      expect(state.noteMode, isFalse);
    },
  );

  test(
    'a question recorded into nothing is not sent, and returns to the invite',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.handTap();
      notifier.conversaTap();
      await settle();
      harness.recorder.returnsEmpty = true;
      notifier.conversaTap();
      await settle();

      expect(
        harness.inbox.questionsSent,
        isEmpty,
        reason:
            'a pergunta sem um byte dentro entrava na caixa e ficava esperando '
            'resposta de um facilitador que não tinha o que ouvir',
      );
      final state = container.read(salaSessionProvider);
      expect(
        state.needsPerson,
        isFalse,
        reason:
            'levantar a mão e perguntar no vazio volta ao convite em silêncio, como '
            'qualquer outra captura vazia',
      );
      expect(state.noteMode, isFalse);
    },
  );

  test('the next passage does not inherit the last one\'s retell', () {
    withDiskThatAnswersAtOnce(
      () => fakeAsync((async) {
        final harness = SalaHarness(filaEmMemoria: true);
        harness.room.verdictChecked = false;
        ProviderContainer? container;
        var antes = 0;
        var told = false;
        addTearDown(() => container?.dispose());

        unawaited(() async {
          container = await inConversaHarness(harness);
          final notifier = container!.read(salaSessionProvider.notifier);
          Future<void> confirm() async {
            notifier.retroTap();
            await settle();
            await notifier.confirmarTraducao();
          }

          notifier.goEnsaio();
          notifier.ensaioTap();
          notifier.ensaioTap();
          await settle();
          notifier.takeKeep();
          notifier.startRetro();
          await settle();
          harness.playback.at = const Duration(seconds: 12);
          notifier.cortarTrecho();
          notifier.retroTap();
          await settle();
          await confirm();
          await settle();
          harness.playback.finishPlayback();
          await settle();
          // A aterragem no trecho não contado é a porta que arma um conserto: é o que a
          // passagem seguinte não pode herdar.
          harness.room.verdictUntoldSegmentId =
              harness.room.segments.last.segmentId;
          await notifier.finishBackTranslation();
          await settle();

          notifier.leaveThePassage();
          await settle();
          harness.room.chunkSpans.clear();
          antes = harness.room.replacesAsked.length;

          notifier.entrarNaOferecida();
          await settle();
          notifier.goEnsaio();
          notifier.ensaioTap();
          notifier.ensaioTap();
          await settle();
          notifier.takeKeep();
          notifier.startRetro();
          await settle();
          harness.playback.at = const Duration(seconds: 9);
          notifier.cortarTrecho();
          notifier.retroTap();
          await settle();
          await confirm();
          await settle();
          told = true;
        }());
        async.elapse(const Duration(seconds: 10));
        expect(told, isTrue);

        expect(
          harness.room.chunkSpans,
          ['0-9000'],
          reason:
              'o primeiro trecho de uma retro nova sobe com o vão do tocador, e não com os '
              'limites que a aterragem da passagem anterior tinha deixado para trás',
        );
        expect(
          harness.room.replacesAsked.length,
          antes,
          reason:
              'e como pedaço novo, não como correção de um trecho da passagem que a equipe '
              'já deixou',
        );
      }),
    );
  });

  test('a fresh passage does not inherit the last one\'s strikes', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.succeeds = false;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'uma falha ainda não chama ninguém',
    );

    // Entered with the room still failing, because a turn that lands resets the counters
    // itself — the inheritance only shows when the new passage stumbles too.
    notifier.leaveThePassage();
    await settle();
    notifier.entrarNaOferecida();
    await settle();

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'a passagem nova começava com as faltas da anterior e parava na primeira',
    );
  });

  test(
    'an inbox that cannot be asked three times in a row does not stop the room',
    () async {
      final harness = SalaHarness(
        settleDelay: const Duration(milliseconds: 20),
      );
      harness.inbox.cannotBeAsked = true;
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      for (var turno = 0; turno < 3; turno++) {
        notifier.conversaTap();
        await settle();
        notifier.conversaTap();
        await settle();
      }

      expect(
        container.read(salaSessionProvider).needsPerson,
        isFalse,
        reason:
            'chave rotacionada, 500 e timeout liam como "não há respostas"; a mesma '
            'leitura silenciosa que a caixa de replies dela faz num fetch que falhou, '
            'sem parar a conversa que segue rodando',
      );
    },
  );

  test('a fixed line spoken three times in a row does not stop the room', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.turnsAreCanned = true;
    harness.room.fixedLine = 'D0';

    for (var turno = 0; turno < 3; turno++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    final ditas = harness.voice.fixedLines
        .where((line) => line == ('D0', testLanguage))
        .length;
    expect(
      ditas,
      3,
      reason:
          'a parada é na terceira; um teste que não chega lá passa sem nunca ter '
          'exercido a contagem que ele existe para prender',
    );
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason:
          'três turnos de emergência seguidos não podem parar a sessão para um '
          'facilitador que não estava na casa',
    );
  });

  test(
    'a turn that says nothing about coverage leaves the necklace alone',
    () async {
      final harness = SalaHarness(
        settleDelay: const Duration(milliseconds: 30),
      );
      harness.room.nextCoverage = coverage(engaged: 3, surfaced: 5);
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      expect(container.read(salaSessionProvider).coverage.engaged, 3);

      harness.room.silentAboutCoverage = true;
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();

      expect(
        container.read(salaSessionProvider).coverage.engaged,
        3,
        reason:
            'campo ausente lido como zero esvaziava o colar no meio da passagem — o '
            'único registro de progresso que essa equipe percebe',
      );
    },
  );

  test('coming back to a passage reopens the same session', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    final aberta = container.read(salaSessionProvider).sessionId;
    expect(aberta, isNotNull);

    notifier.leaveThePassage();
    await settle();
    expect(
      container.read(salaSessionProvider).comecadas,
      contains('P01'),
      reason:
          'a régua desenha essas mais altas, porque voltar a uma é outro ato',
    );

    harness.room.pericopesAsked.clear();
    notifier.entrarNaOferecida();
    await settle();

    expect(
      container.read(salaSessionProvider).sessionId,
      aberta,
      reason:
          'sair abandonava a sessão no servidor para sempre — e o servidor não a '
          'reencontra, porque ir_sessions não guarda aparelho',
    );
    expect(
      harness.room.pericopesAsked,
      isEmpty,
      reason: 'e não se cria outra em cima da que já existe',
    );
  });

  test('a passage carried to the end stops being work in progress', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    // Entered through the wheel, because a resume point is a passage: `goConversa()` with
    // no pericope has nothing to remember.
    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();

    notifier.goEnsaio();
    await settle();
    expect(await harness.emAberto.startedIn('Ruth'), contains('P01'));

    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();
    await notifier.aprovarRascunhoFinal();
    await settle(const Duration(milliseconds: 900));

    expect(
      await harness.emAberto.startedIn('Ruth'),
      isEmpty,
      reason:
          'uma passagem aprovada não é trabalho em aberto — conferida '
          'ainda é: a equipe pode fechar o app antes de aprovar, e tem de '
          'voltar ao gesto que falta',
    );
  });

  test(
    'a session the server forgot twice sends the team back to the wheel',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      notifier.leaveThePassage();
      await settle();

      harness.room.failHeldTurnWith = const SessionGone();
      harness.room.failCreateOnceWith = const SessionGone();
      notifier.entrarNaOferecida();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.escolha,
        reason:
            'a sessão lembrada e a sessão nova recusada de novo — sem ficar '
            'presa numa conversa que não abre, a equipe volta à roda',
      );
      expect(state.needsPerson, isFalse);
    },
  );

  test('hearing again is not offered on top of the retro clip', () async {
    final harness = SalaHarness();
    harness.room.verdictChecked = false;
    harness.room.verdictHasFinding = true;
    harness.room.verdictFindingSegmentId = 'trecho-nenhum';
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btPhase, BtPhase.findings);
    expect(state.lastSpoken, isNotNull);
    expect(state.voice, VoiceState.invite);
    expect(state.canHearAgain, isFalse);
  });
}

Future<ProviderContainer> inConversaHarness(SalaHarness harness) async {
  final container = harness.container();
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}
