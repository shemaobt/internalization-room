import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show
        enterThePanorama,
        enterThePassage,
        settle,
        theChoiceOffersAPassage,
        withDiskThatAnswersAtOnce;

void main() {
  test(
    'a book with nothing left to offer shows it is done and calls nobody',
    () async {
      final harness = SalaHarness()..room.passages = const [];
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.naRoda, isEmpty);
      expect(state.needsPerson, isFalse);
      expect(
        state.livroInteiroFeito,
        isTrue,
        reason: 'o servidor mesmo não devolveu nenhuma passagem',
      );
      expect(
        harness.voice.fixedLines,
        isNot(contains(('E0', testLanguage))),
        reason: 'o círculo parado já é o aviso; o app não fala por cima dele',
      );
    },
  );

  test('leaving a passage goes back to the wheel and keeps it there', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);

    notifier.leaveThePassage();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.escolha);
    expect(state.naRoda, hasLength(3));
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
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
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
    'three passages that all cannot open each send the team back to the Menu, '
    'each hitting the door once',
    () async {
      final harness = SalaHarness()
        ..room.passagesThatCannotOpen = {'P01', 'P02', 'P03'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      for (final pericope in ['P01', 'P02', 'P03']) {
        await enterThePassage(notifier, read, pericope);
        await settle();
        expect(read().station, isA<Menu>());
        expect(read().needsPerson, isFalse);
      }

      expect(
        harness.room.calls.where((call) => call == 'createSession'),
        hasLength(3),
        reason: 'cada toque na roda tem de bater na porta de novo',
      );
      expect(harness.room.personsAsked, 0);
      expect(harness.voice.fixedLines, isNot(contains(('E0', testLanguage))));
    },
  );

  test(
    'a remembered session reset and a passage the room cannot open rest the team with no sign and no call',
    () async {
      final harness = SalaHarness()
        ..emAberto.forgetsTheSessionAfter = const Duration(milliseconds: 500);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await theChoiceOffersAPassage(container);
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
      await waitFor(
        'a passagem abrir',
        () => container.read(salaSessionProvider).sessionId != null,
      );
      notifier.leaveThePassage();
      await waitFor(
        'a sala voltar à Escolha com o lugar da passagem guardado',
        () async =>
            container.read(salaSessionProvider).stage == SalaStage.escolha &&
            container.read(salaSessionProvider).entriesOpen &&
            container.read(salaSessionProvider).voice == VoiceState.invite &&
            await harness.emAberto.of('Ruth', 'P01', 'pt') != null,
      );
      expect(await harness.emAberto.of('Ruth', 'P01', 'pt'), isNotNull);

      harness.room.forgetTheSession(harness.room.sessionIds.single);
      harness.room.passagesThatCannotOpen = {'P01'};
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
      await waitFor(
        'a sala descansar',
        () =>
            harness.room.passagesThatCannotOpen.isNotEmpty &&
            !container.read(salaSessionProvider).awaitingTheGuide,
      );
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
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
      harness.emAberto.rows['Ruth/P01/en'] = noutraLingua;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.stage, SalaStage.escolha);
      expect(state.needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(
        await harness.emAberto.of('Ruth', 'P01', 'en'),
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
        ..room.passages = const [
          Passagem(
            pericope: 'OV-Ruth',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
            book: 'Ruth',
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ]
        ..room.passagesThatCannotOpen = {'OV-Ruth'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePanorama(notifier, read);
      await waitFor(
        'a sala bater na porta',
        () => harness.room.calls.contains('createSession'),
      );
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
            pericope: 'OV-Ruth',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
            book: 'Ruth',
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ]
        ..room.passagesThatCannotOpen = {'OV-Ruth'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();
      for (var attempt = 0; attempt < 3; attempt++) {
        notifier.openTheEntry(
          container.read(salaSessionProvider).naRoda!.first,
        );
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
    'a refused wheel stops for nothing: no person, the invite at rest',
    () async {
      final harness = SalaHarness()
        ..room.failWith = const Refused('UNAUTHORIZED');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.abrirEscolha();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.voice, VoiceState.invite);
      expect(state.needsPerson, isFalse);
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
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
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
    notifier.gravarACena(1);
    notifier.gravarACena(1);
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

    final replyAt = harness.sounds.lastIndexOf('voice:line');
    notifier.conversaTap();
    await waitFor(
      'o microfone abrir',
      () => harness.sounds.contains('recorder:start'),
    );

    final heard = harness.sounds.sublist(replyAt);
    expect(
      heard.indexOf('voice:stop'),
      allOf(isNonNegative, lessThan(heard.indexOf('recorder:start'))),
      reason: 'a resposta para antes do microfone abrir',
    );
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

  test('leaving a passage does not strand the take on disk', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.gravarACena(1);
    notifier.gravarACena(1);
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
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await settle();
    notifier.takeKeep();
    await waitFor('a sala nomear a parte', () {
      final partes = container.read(salaSessionProvider).partes;
      return partes.isNotEmpty && partes.last.takeId != null;
    });
    await untilTheAdvanceDiscLights(notifier);
    notifier.startRetro();
    await settle();

    harness.room.failChunkWith = const Refused('BAD_REQUEST');
    harness.playback.at = const Duration(seconds: 12);
    notifier.retroTap();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'um trecho da retro falhar',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
    );

    harness.room.failChunkWith = null;
    harness.playback.at = const Duration(seconds: 30);
    notifier.retroTap();
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

  test('a rehearsal that will not play never opens the terminei', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await settle();
    notifier.takeKeep();
    await untilTheAdvanceDiscLights(notifier);
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
    'a rehearsal with nothing recorded keeps the team on it, its circle live',
    () async {
      final harness = SalaHarness();
      final container = await inConversaHarness(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      await settle();
      notifier.startRetro();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(
        state.stage,
        SalaStage.ensaio,
        reason: 'não haver ensaio nenhum não abre a tradução',
      );
      expect(state.needsPerson, isFalse);
      notifier.gravarACena(1);
      await settle();
      expect(
        container.read(salaSessionProvider).ensaio,
        EnsaioStatus.recording,
        reason: 'e o círculo continua a gravar: a sala não fica sem saída',
      );
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
      notifier.gravarACena(1);
      notifier.gravarACena(1);
      await settle();
      notifier.takeKeep();
      await settle();
      await untilTheWoodPlayLights(notifier);
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
      notifier.gravarACena(2);
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

  test('a session read that says a person is needed raises no sign and the app '
      'announces nothing', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 30));
    harness.room.serverStatus = 'needs_person';
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);

    await waitFor(
      'a vigia ler a sessão',
      () => harness.room.calls.contains('fetchState'),
    );
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    expect(
      harness.voice.fixedLines,
      isNot(contains(('E0', testLanguage))),
      reason:
          'a leitura de estado não é um turno; quem fala E0 é o servidor, '
          'no turno em que ele decidir, não a vigia que só leu a marca',
    );
  });

  test('a session the room forgot does not keep being told about it', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
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
    'a wheel that keeps failing to load never calls a person, retry after retry',
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

      expect(container.read(salaSessionProvider).needsPerson, isFalse);
    },
  );

  test(
    'a kept take still reaches the queue when the room is disposed',
    () async {
      final harness = SalaHarness(
        takesOverride: (room, home, recordings) => QueueThatEnqueuesLate(
          room: room,
          home: () async => home,
          recordings: recordings,
        )..enqueuesAfter = const Duration(milliseconds: 700),
      );
      final container = await inConversaHarness(harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      notifier.gravarACena(1);
      notifier.gravarACena(1);
      await settle();
      notifier.takeKeep();
      container.dispose();
      await waitFor(
        'a gravação guardada chegar à fila (a guarda contra ler providers '
        'descartados foi posta antes do enfileiramento, no método cujo '
        'trabalho é não perder gravação)',
        () async =>
            (await harness.takes.entries()).isNotEmpty ||
            harness.room.takesKept.isNotEmpty,
      );
    },
  );

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
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
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
    notifier.gravarACena(1);
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
      final harness = SalaHarness()
        ..room.bridgeMode = 'calibration_pending'
        ..room.passages = const [
          Passagem(
            pericope: 'OV-Ruth',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
            book: 'Ruth',
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ];
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePanorama(notifier, read);
      await waitFor('o panorama ser dito', () => read().panoramaSaid);

      harness.recorder.returnsNothing = true;
      notifier.panoramaTap();
      await settle();
      notifier.panoramaTap();
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
          }

          notifier.goEnsaio();
          notifier.gravarACena(1);
          notifier.gravarACena(1);
          await settle();
          notifier.takeKeep();
          await untilTheAdvanceDiscLights(notifier);
          notifier.startRetro();
          await settle();
          harness.playback.at = const Duration(seconds: 12);
          notifier.retroTap();
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

          notifier.openTheEntry(
            container!.read(salaSessionProvider).naRoda!.first,
          );
          await settle();
          notifier.goEnsaio();
          notifier.gravarACena(1);
          notifier.gravarACena(1);
          await settle();
          notifier.takeKeep();
          await untilTheAdvanceDiscLights(notifier);
          notifier.startRetro();
          await settle();
          harness.playback.at = const Duration(seconds: 9);
          notifier.retroTap();
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
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
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
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();

    expect(
      container.read(salaSessionProvider).sessionId,
      aberta,
      reason:
          'sair abandonava a sessão no servidor para sempre — e o servidor não a '
          'reencontra, porque ir_sessions não guarda aparelho',
    );
    expect(
      harness.room.sessionIds,
      [aberta],
      reason: 'e não se cria outra em cima da que já existe',
    );
  });

  test(
    'an approved passage stays work in progress, on its approved draft',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      // Entered through the wheel, because a resume point is a passage: `goConversa(book: 'Ruth')` with
      // no pericope has nothing to remember.
      await notifier.abrirEscolha();
      await settle();
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
      await settle();

      notifier.goEnsaio();
      await settle();
      expect(await harness.emAberto.startedIn('Ruth', 'pt'), contains('P01'));

      notifier.gravarACena(1);
      notifier.gravarACena(1);
      await settle();
      notifier.takeKeep();
      await untilTheAdvanceDiscLights(notifier);
      notifier.startRetro();
      await settle();
      harness.playback.finishPlayback();
      await settle();
      await notifier.finishBackTranslation();
      await settle();
      await notifier.aprovarRascunhoFinal();
      await settle(const Duration(milliseconds: 900));

      expect(
        await harness.emAberto.startedIn('Ruth', 'pt'),
        contains('P01'),
        reason:
            'aprovada, a passagem segue para a checagem externa a partir da '
            'tradução conferida: o ponto de retomada fica nela',
      );
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
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await settle();
    notifier.takeKeep();
    await untilTheAdvanceDiscLights(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btPhase, BtPhase.playing);
    expect(state.btVeredito, isTrue);
    expect(state.lastSpoken, isNotNull);
    expect(state.voice, VoiceState.invite);
    expect(state.canHearAgain, isFalse);
  });
}

Future<ProviderContainer> inConversaHarness(SalaHarness harness) async {
  final container = harness.container();
  await container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
  await settle();
  return container;
}
