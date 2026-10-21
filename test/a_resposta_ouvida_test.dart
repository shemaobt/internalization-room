import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _replyUrl = '/voz/resposta-1';

/// The desk, as far as this tablet can tell: it knows which replies are still to be
/// heard, and it is the only thing that still knows once the screen is gone.
class _Desk {
  final Map<String, bool> heard = {'resposta-1': false};

  /// Where each reply is served from now. A facilitator who records again moves it.
  final Map<String, String> current = {'resposta-1': _replyUrl};

  /// How many times this tablet has read the inbox. The case waits on this rather than
  /// on a reply arriving: after an agreed mark the desk rightly has nothing to offer,
  /// and waiting for a reply there would hang on the desk being correct.
  int reads = 0;

  /// The mark never leaves the tablet.
  bool unreachable = false;

  /// What the desk answers when the mark does reach it.
  int answers = 200;

  /// How many marks have reached the desk.
  int marks = 0;

  /// The clip the last mark said it played, as the desk read it off the wire.
  String? markedUrl;

  Completer<void>? _holding;
  Completer<void>? _theFirstMark;
  Completer<void>? _theReads;

  /// The first mark hangs and then never reaches the desk; later marks are answered.
  void theFirstMarkHangs() => _theFirstMark = Completer<void>();

  void theFirstMarkFailsAtLast() {
    _theFirstMark?.complete();
    _theFirstMark = null;
  }

  void holdsTheReads() => _theReads = Completer<void>();

  void readsAtLast() {
    _theReads?.complete();
    _theReads = null;
  }

  /// Keep the desk from answering, so the window between the tap and the answer can be
  /// looked at instead of assumed away.
  void holdsTheAnswer() => _holding = Completer<void>();

  void answersAtLast() {
    _holding?.complete();
    _holding = null;
  }

  http.Client get client => MockClient((request) async {
    if (request.url.path.endsWith('/questions/replies')) {
      reads++;
      await _theReads?.future;
      return http.Response(
        jsonEncode({
          'replies': [
            for (final row in heard.entries)
              if (!row.value)
                {'question_id': row.key, 'audio_url': current[row.key]},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/heard')) {
      marks++;
      if (marks == 1 && _theFirstMark != null) {
        await _theFirstMark!.future;
        throw const SocketException('sem rede');
      }
      await _holding?.future;
      if (unreachable) throw const SocketException('sem rede');
      final id = request.url.pathSegments[request.url.pathSegments.length - 2];
      markedUrl = request.body.isEmpty
          ? null
          : (jsonDecode(request.body) as Map)['audio_url'] as String?;
      if (markedUrl != null && markedUrl != current[id]) {
        return http.Response('{"code":"REPLY_MOVED_ON"}', 409);
      }
      if (answers >= 200 && answers < 300) heard[id] = true;
      return http.Response('', answers);
    }
    return http.Response('', 404);
  });
}

SalaHarness _tabletTalkingTo(_Desk desk) => SalaHarness(
  inboxService: HandInboxRepository(
    client: desk.client,
    deviceId: () async => 'aparelho-1',
  ),
);

/// Open the room. A second call models the app coming back: fresh state, same desk.
Future<ProviderContainer> _opensTheRoom(_Desk desk, SalaHarness harness) async {
  final before = desk.reads;
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
  await waitFor(
    'o tablet ler a caixa de entrada na mesa',
    () => desk.reads > before,
  );
  await settle();
  return container;
}

Future<void> _theTeamTapsTheHand(ProviderContainer container) async {
  container.read(salaSessionProvider.notifier).handTap();
  await settle();
}

int _timesPlayed(SalaHarness harness) =>
    harness.voice.played.where((url) => url == _replyUrl).length;

Future<void> _theTeamHearsTheReplyAndTheDeskRefusesTheMark(
  _Desk desk,
  ProviderContainer container,
) async {
  final marksBefore = desk.marks;
  await _theTeamTapsTheHand(container);
  await waitFor('a mesa recusar a marca', () => desk.marks > marksBefore);
  await settle();
}

Future<void> _theTeamHearsTheReplyAndTheMarkReachesTheDesk(
  _Desk desk,
  ProviderContainer container,
) async {
  final marksBefore = desk.marks;
  await _theTeamTapsTheHand(container);
  await waitFor('a marca chegar à mesa', () => desk.marks > marksBefore);
  await settle();
}

_Desk _aDeskWithTwoRepliesAndNoMarkAccepted() => _Desk()
  ..answers = 400
  ..heard['resposta-2'] = false
  ..current['resposta-2'] = '/voz/resposta-2';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  test('a reply the desk never learned about is still unheard', () async {
    final desk = _Desk()..unreachable = true;
    final harness = _tabletTalkingTo(desk);
    final container = await _opensTheRoom(desk, harness);

    await _theTeamTapsTheHand(container);
    expect(_timesPlayed(harness), 1, reason: 'a equipe ouviu a resposta');
    await waitFor('a tentativa de marca terminar', () => desk.marks == 1);

    expect(
      container.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-1',
      reason:
          'a marca nunca saiu do tablet, então a sala não pode dizer que '
          'a resposta foi entregue — o servidor vai contradizê-la',
    );

    // O app volta: estado novo, mesma mesa. O que a sala mostrava antes tem de
    // continuar valendo depois, e é aqui que a marca otimista evaporava.
    final again = await _opensTheRoom(desk, harness);
    expect(
      again.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-1',
      reason:
          'antes e depois da reconstrução a sala tem de dizer a mesma '
          'coisa; era aqui que ela mudava de ideia sozinha',
    );
  });

  test('a reply the player cannot decode is never stamped heard', () async {
    final desk = _Desk();
    final harness = _tabletTalkingTo(desk)..voice.succeeds = false;
    final container = await _opensTheRoom(desk, harness);

    await _theTeamTapsTheHand(container);
    expect(_timesPlayed(harness), 1, reason: 'a sala tentou tocar a resposta');

    expect(
      desk.marks,
      0,
      reason:
          'o player falhou na hora e a sala não tocou nada, mas quinze '
          'milissegundos depois o tablet marcava a resposta como ouvida',
    );
    expect(desk.heard['resposta-1'], isFalse);
    final state = container.read(salaSessionProvider);
    expect(
      state.oldestUnheardReply?.id,
      'resposta-1',
      reason: 'uma resposta que ninguém ouviu continua oferecida à mão',
    );
    expect(
      state.playingReplyId,
      isNull,
      reason: 'a mão e o círculo voltam à equipe quando o clipe não toca',
    );
  });

  test('a reply the room could not serve is never stamped heard', () async {
    final desk = _Desk();
    final harness = _tabletTalkingTo(desk);
    final container = await _opensTheRoom(desk, harness);
    harness.voice.roomFailsWith = const Refused('BAD_REQUEST');

    await _theTeamTapsTheHand(container);
    expect(_timesPlayed(harness), 1, reason: 'a sala tentou tocar a resposta');

    expect(
      desk.marks,
      0,
      reason:
          'a queda da sala no download do clipe era engolida como um play '
          'qualquer, e a mesa recebia a marca de uma resposta que não soou',
    );
    final state = container.read(salaSessionProvider);
    expect(state.oldestUnheardReply?.id, 'resposta-1');
    expect(state.playingReplyId, isNull);
    expect(
      state.needsPerson,
      isFalse,
      reason:
          'a mão é um canal lateral: a resposta que não chegou não chama ninguém',
    );
  });

  test(
    'a reply that fails to sound twice is set aside and the hand asks',
    () async {
      final desk = _Desk();
      final harness = _tabletTalkingTo(desk)..voice.succeeds = false;
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      expect(
        container.read(salaSessionProvider).oldestUnheardReply?.id,
        'resposta-1',
        reason: 'a primeira falha ainda não tirava a resposta da mão',
      );

      await _theTeamTapsTheHand(container);
      final setAside = container.read(salaSessionProvider);
      expect(
        setAside.oldestUnheardReply,
        isNull,
        reason:
            'a resposta que não toca seguia na mão a cada toque, para sempre',
      );
      expect(setAside.hasUnheardReply, isFalse);

      await _theTeamTapsTheHand(container);
      expect(
        _timesPlayed(harness),
        2,
        reason: 'a sala tentou uma terceira vez o clipe que já falhou duas',
      );
      expect(
        container.read(salaSessionProvider).noteMode,
        isTrue,
        reason: 'a equipe não conseguia levantar uma pergunta nova',
      );
      expect(
        desk.marks,
        0,
        reason:
            'nenhuma marca sai do tablet por uma resposta que ninguém ouviu',
      );
      expect(desk.heard['resposta-1'], isFalse);
    },
  );

  test(
    'a clip the room cannot serve twice is set aside like any other',
    () async {
      final desk = _Desk();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);
      harness.voice.roomFailsWith = const Refused('BAD_REQUEST');

      await _theTeamTapsTheHand(container);
      await _theTeamTapsTheHand(container);
      expect(
        container.read(salaSessionProvider).hasUnheardReply,
        isFalse,
        reason:
            'a sala não distingue clipe que não chegou de clipe que não toca',
      );

      await _theTeamTapsTheHand(container);
      expect(_timesPlayed(harness), 2);
      expect(container.read(salaSessionProvider).noteMode, isTrue);
      expect(container.read(salaSessionProvider).needsPerson, isFalse);
      expect(desk.marks, 0);
    },
  );

  test('a reply set aside lets the next unheard reply through', () async {
    final desk = _Desk()
      ..heard['resposta-2'] = false
      ..current['resposta-2'] = '/voz/resposta-2';
    final harness = _tabletTalkingTo(desk)..voice.refuses.add(_replyUrl);
    final container = await _opensTheRoom(desk, harness);

    await _theTeamTapsTheHand(container);
    await _theTeamTapsTheHand(container);
    expect(
      container.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-2',
      reason:
          'a resposta de trás nunca chegava à mão, presa atrás da que falha',
    );

    await _theTeamTapsTheHand(container);
    await waitFor(
      'a mesa registrar a escuta da segunda resposta',
      () => desk.heard['resposta-2'] == true,
    );
    expect(harness.voice.played.last, '/voz/resposta-2');
    expect(desk.markedUrl, '/voz/resposta-2');
    expect(desk.marks, 1, reason: 'só a resposta que soou chega à mesa');
    expect(desk.heard['resposta-1'], isFalse);
  });

  test('a reply set aside is offered again at a new address', () async {
    const recordedAgain = '/voz/resposta-1-regravada';
    final desk = _Desk()
      ..heard['resposta-2'] = false
      ..current['resposta-2'] = '/voz/resposta-2';
    final harness = _tabletTalkingTo(desk)..voice.refuses.add(_replyUrl);
    final container = await _opensTheRoom(desk, harness);
    await _theTeamTapsTheHand(container);
    await _theTeamTapsTheHand(container);
    expect(
      container.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-2',
    );

    desk.current['resposta-1'] = recordedAgain;
    desk.answers = 400;
    final readsBefore = desk.reads;
    await _theTeamTapsTheHand(container);
    await waitFor(
      'a sala reler a caixa de entrada depois da marca recusada',
      () => desk.reads > readsBefore,
    );
    await settle();
    expect(
      container.read(salaSessionProvider).oldestUnheardReply?.audioUrl,
      recordedAgain,
      reason: 'a facilitadora regravou e a quarentena do endereço velho ficou',
    );

    desk.answers = 200;
    await _theTeamTapsTheHand(container);
    await waitFor(
      'a mesa registrar a escuta da regravação',
      () => desk.heard['resposta-1'] == true,
    );
    expect(harness.voice.played.last, recordedAgain);
    expect(desk.markedUrl, recordedAgain);
  });

  test(
    'a play cut off by a new generation does not count against the reply',
    () async {
      final desk = _Desk();
      final harness = _tabletTalkingTo(desk)..voice.succeeds = false;
      final container = await _opensTheRoom(desk, harness);
      harness.voice.holdNextLine();

      container.read(salaSessionProvider.notifier).handTap();
      await settle();
      final readsBefore = desk.reads;
      unawaited(
        container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
      );
      await waitFor(
        'a sala reler a caixa de entrada',
        () => desk.reads > readsBefore,
      );
      await settle();
      harness.voice.finishHeldLine();
      await settle();

      await _theTeamTapsTheHand(container);
      expect(
        container.read(salaSessionProvider).oldestUnheardReply?.id,
        'resposta-1',
        reason:
            'um play cortado ao recomeçar a conversa gastava uma das duas falhas '
            'de um clipe que ninguém pôde julgar',
      );
    },
  );

  test(
    'a reply that did not sound is offered again at the address the facilitator recorded it to',
    () async {
      const recordedAgain = '/voz/resposta-1-regravada';
      final desk = _Desk();
      final harness = _tabletTalkingTo(desk)..voice.refuses.add(_replyUrl);
      final container = await _opensTheRoom(desk, harness);
      desk.current['resposta-1'] = recordedAgain;
      final readsBefore = desk.reads;

      await _theTeamTapsTheHand(container);
      await waitFor(
        'a sala reler a caixa de entrada depois da falha',
        () => desk.reads > readsBefore,
      );
      await settle();

      expect(
        container.read(salaSessionProvider).oldestUnheardReply?.audioUrl,
        recordedAgain,
        reason:
            'a facilitadora viu "não ouvida" na mesa e regravou, mas a mão '
            'seguia oferecendo o endereço velho até a próxima leitura agendada, '
            'que na convite não vem',
      );

      await _theTeamTapsTheHand(container);
      await waitFor(
        'a mesa registrar a escuta da regravação',
        () => desk.heard['resposta-1'] == true,
      );
      expect(harness.voice.played.last, recordedAgain);
      expect(desk.markedUrl, recordedAgain);
    },
  );

  test('a desk that refuses the mark is not taken as agreement', () async {
    final desk = _Desk()..answers = 400;
    final harness = _tabletTalkingTo(desk);
    final container = await _opensTheRoom(desk, harness);

    await _theTeamTapsTheHand(container);
    expect(_timesPlayed(harness), 1);
    await waitFor('a mesa recusar a marca', () => desk.marks == 1);

    expect(
      container.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-1',
      reason:
          'a chamada chegou e voltou recusada; uma recusa e um sim nunca '
          'foram a mesma coisa, mas a resposta do servidor não era olhada',
    );

    final again = await _opensTheRoom(desk, harness);
    expect(
      again.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-1',
    );
  });

  test(
    'a reply that moved on while it played is offered again at its new address',
    () async {
      const recordedAgain = '/voz/resposta-1-regravada';
      final desk = _Desk()..holdsTheAnswer();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      expect(_timesPlayed(harness), 1);
      await waitFor('a marca chegar à mesa', () => desk.marks == 1);

      // While the tablet waits on its mark, the facilitator records again.
      final readsBefore = desk.reads;
      desk.current['resposta-1'] = recordedAgain;
      desk.answersAtLast();
      await waitFor(
        'a sala reler a caixa de entrada depois da recusa',
        () => desk.reads > readsBefore,
      );
      await settle();

      expect(desk.heard['resposta-1'], isFalse);
      expect(
        container.read(salaSessionProvider).oldestUnheardReply?.audioUrl,
        recordedAgain,
        reason:
            'a mesa recusou a marca do clipe velho e a pergunta segue oferecida, '
            'já no endereço novo — sem a releitura a mão oferecia um clipe que '
            'não soa e cuja marca a mesa recusa de novo, até a próxima leitura '
            'agendada, que na convite não vem',
      );

      await _theTeamTapsTheHand(container);
      await waitFor(
        'a mesa registrar a escuta da regravação',
        () => desk.heard['resposta-1'] == true,
      );
      expect(harness.voice.played.last, recordedAgain);
      expect(desk.markedUrl, recordedAgain);
    },
  );

  test(
    'a reply whose heard mark the desk refuses twice is set aside and the next tap plays the newer reply',
    () async {
      final desk = _aDeskWithTwoRepliesAndNoMarkAccepted();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);
      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);
      expect(_timesPlayed(harness), 2);

      await _theTeamTapsTheHand(container);
      expect(
        harness.voice.played.last,
        '/voz/resposta-2',
        reason:
            'a resposta cuja marca a mesa recusou duas vezes seguia na mão, '
            'presa na frente da que veio depois',
      );
      expect(_timesPlayed(harness), 2);
    },
  );

  test(
    'a reply whose heard mark the desk refuses twice is set aside and the next tap arms note mode when no other reply waits',
    () async {
      final desk = _Desk()..answers = 400;
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);
      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);

      await _theTeamTapsTheHand(container);
      expect(
        _timesPlayed(harness),
        2,
        reason: 'a sala tocou pela terceira vez a resposta que a mesa recusa',
      );
      expect(
        container.read(salaSessionProvider).noteMode,
        isTrue,
        reason: 'a equipe não conseguia levantar uma pergunta nova',
      );
      expect(desk.heard['resposta-1'], isFalse);
    },
  );

  test(
    'one failed sound then one refused heard mark on the same reply set it aside',
    () async {
      final desk = _Desk()..answers = 400;
      final harness = _tabletTalkingTo(desk)..voice.succeeds = false;
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      expect(desk.marks, 0);
      harness.voice.succeeds = true;
      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);

      await _theTeamTapsTheHand(container);
      expect(
        _timesPlayed(harness),
        2,
        reason: 'a falha de som e a marca recusada somavam duas e não bastavam',
      );
      expect(container.read(salaSessionProvider).noteMode, isTrue);
    },
  );

  test(
    'a relaunch after a set-aside offers the reply again and it needs two failures again',
    () async {
      final desk = _Desk()..answers = 400;
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);
      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);
      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);
      await _theTeamTapsTheHand(container);
      expect(_timesPlayed(harness), 2);

      final again = await _opensTheRoom(desk, harness);
      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, again);
      expect(_timesPlayed(harness), 3);

      await _theTeamTapsTheHand(again);
      expect(
        _timesPlayed(harness),
        4,
        reason: 'uma única recusa depois da reabertura já a punha de lado',
      );
    },
  );

  test('a heard mark that never reaches the desk counts nothing', () async {
    final desk = _Desk()..unreachable = true;
    final harness = _tabletTalkingTo(desk);
    final container = await _opensTheRoom(desk, harness);

    for (var taps = 0; taps < 3; taps++) {
      await _theTeamHearsTheReplyAndTheMarkReachesTheDesk(desk, container);
    }

    expect(_timesPlayed(harness), 3);
  });

  test(
    'a refused mark on the old address leaves the reply at its new address untouched',
    () async {
      const recordedAgain = '/voz/resposta-1-regravada';
      final desk = _Desk()
        ..answers = 400
        ..holdsTheAnswer();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      await waitFor('a marca chegar à mesa', () => desk.marks == 1);
      desk.current['resposta-1'] = recordedAgain;
      final readsBefore = desk.reads;
      container.read(salaSessionProvider.notifier).lookForReplies();
      await waitFor('a sala reler a caixa', () => desk.reads > readsBefore);
      await settle();
      desk.answersAtLast();
      await settle();

      await _theTeamHearsTheReplyAndTheDeskRefusesTheMark(desk, container);
      await _theTeamTapsTheHand(container);
      expect(
        harness.voice.played.where((url) => url == recordedAgain).length,
        2,
        reason:
            'a recusa da marca do endereço velho contou contra a resposta '
            'regravada, que já nascia com uma falha',
      );
    },
  );

  test(
    'a mark refused after the room left the conversation leaves the reply offered',
    () async {
      final desk = _Desk()
        ..answers = 400
        ..holdsTheAnswer();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      await waitFor('a marca chegar à mesa', () => desk.marks == 1);
      container.read(salaSessionProvider.notifier).goEnsaio();
      await settle();
      desk.answersAtLast();
      await settle();
      await settle();

      expect(
        container.read(salaSessionProvider).oldestUnheardReply?.audioUrl,
        _replyUrl,
        reason:
            'a marca recusada depois da troca de tela deixou a resposta como '
            'ouvida até a reabertura',
      );
    },
  );

  test(
    'a mark refused after the room left the conversation brings the reply at its new address',
    () async {
      const recordedAgain = '/voz/resposta-1-regravada';
      final desk = _Desk()
        ..answers = 400
        ..holdsTheAnswer();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      await waitFor('a marca chegar à mesa', () => desk.marks == 1);
      container.read(salaSessionProvider.notifier).goEnsaio();
      await settle();
      desk.current['resposta-1'] = recordedAgain;
      desk.answersAtLast();
      await settle();
      await settle();

      expect(
        container.read(salaSessionProvider).oldestUnheardReply?.audioUrl,
        recordedAgain,
        reason:
            'a recusa depois da troca de tela não releu a caixa e a mão seguia '
            'oferecendo o clipe que a facilitadora já substituiu',
      );
    },
  );

  test(
    'a mark that fails late does not take back a newer mark the desk accepted',
    () async {
      final desk = _Desk()..theFirstMarkHangs();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      await waitFor('a marca chegar à mesa', () => desk.marks == 1);
      final readsBefore = desk.reads;
      unawaited(
        container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
      );
      await waitFor('a sala reler a caixa', () => desk.reads > readsBefore);
      await settle();
      await _theTeamTapsTheHand(container);
      await waitFor(
        'a mesa registrar a escuta',
        () => desk.heard['resposta-1'] == true,
      );
      await settle();
      expect(_timesPlayed(harness), 2);

      desk.holdsTheReads();
      desk.theFirstMarkFailsAtLast();
      await settle();

      expect(
        container.read(salaSessionProvider).oldestUnheardReply,
        isNull,
        reason:
            'a marca velha que falhou tarde devolveu à mão a resposta que a '
            'mesa já aceitou como ouvida',
      );
      desk.readsAtLast();
      await settle();
    },
  );

  test('a reply the desk agrees was heard is never played again', () async {
    final desk = _Desk();
    final harness = _tabletTalkingTo(desk);
    final container = await _opensTheRoom(desk, harness);

    await _theTeamTapsTheHand(container);
    expect(_timesPlayed(harness), 1);
    await waitFor(
      'a mesa registrar que a resposta foi ouvida',
      () => desk.heard['resposta-1'] == true,
    );

    expect(
      desk.markedUrl,
      _replyUrl,
      reason:
          'a marca diz qual clipe tocou: só assim a mesa deixa de carimbar '
          'como ouvida uma resposta regravada enquanto a primeira soava',
    );
    expect(container.read(salaSessionProvider).oldestUnheardReply, isNull);

    final again = await _opensTheRoom(desk, harness);
    await _theTeamTapsTheHand(again);
    expect(
      _timesPlayed(harness),
      1,
      reason:
          'tocar de novo o que a equipe já ouviu é o dano que esta fatia '
          'existe para impedir — e nunca marcar nada faria exatamente isso',
    );
  });

  test(
    'a reply whose mark has not been answered yet is not offered again',
    () async {
      final desk = _Desk()..holdsTheAnswer();
      final harness = _tabletTalkingTo(desk);
      final container = await _opensTheRoom(desk, harness);

      await _theTeamTapsTheHand(container);
      expect(_timesPlayed(harness), 1);
      await waitFor('a marca chegar à mesa', () => desk.marks == 1);

      // A mesa ainda não respondeu. A equipe toca de novo.
      await _theTeamTapsTheHand(container);

      expect(
        _timesPlayed(harness),
        1,
        reason:
            'entre o toque e a resposta da mesa a sala não pode voltar a '
            'oferecer a mesma resposta — é a mesma repetição do terceiro caso, '
            'dentro de uma sessão em vez de entre duas',
      );
      expect(desk.marks, 1, reason: 'nem marcar a mesma resposta duas vezes');

      desk.answersAtLast();
      await settle();
      expect(container.read(salaSessionProvider).oldestUnheardReply, isNull);
    },
  );
}
