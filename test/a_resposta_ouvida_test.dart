import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

const _replyUrl = '/voz/resposta-1';

/// The desk, as far as this tablet can tell: it knows which replies are still to be
/// heard, and it is the only thing that still knows once the screen is gone.
class _Desk {
  final Map<String, bool> heard = {'resposta-1': false};

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
      return http.Response(
        jsonEncode({
          'replies': [
            for (final row in heard.entries)
              if (!row.value)
                {'question_id': row.key, 'audio_url': '/voz/${row.key}'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/heard')) {
      marks++;
      await _holding?.future;
      if (unreachable) throw const SocketException('sem rede');
      final id = request.url.pathSegments[request.url.pathSegments.length - 2];
      markedUrl = request.body.isEmpty
          ? null
          : (jsonDecode(request.body) as Map)['audio_url'] as String?;
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
  await container.read(salaSessionProvider.notifier).goConversa();
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

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
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

  test('a desk that refuses the mark is not taken as agreement', () async {
    final desk = _Desk()..answers = 500;
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

  test('a reply that moved on while it played is still offered', () async {
    final desk = _Desk()..answers = 409;
    final harness = _tabletTalkingTo(desk);
    final container = await _opensTheRoom(desk, harness);

    await _theTeamTapsTheHand(container);
    expect(_timesPlayed(harness), 1);
    await waitFor('a mesa dizer que a resposta mudou', () => desk.marks == 1);

    expect(
      container.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-1',
      reason:
          'a facilitadora regravou enquanto a primeira tocava; a mesa recusou '
          'a marca do clipe velho e a pergunta segue oferecida, com o clipe novo',
    );

    final again = await _opensTheRoom(desk, harness);
    expect(
      again.read(salaSessionProvider).oldestUnheardReply?.id,
      'resposta-1',
    );
  });

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
