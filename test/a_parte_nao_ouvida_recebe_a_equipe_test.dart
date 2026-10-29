import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

class _UmaSalaDeAntesDe19DeOutubro extends FakeRoom {
  Map<String, Object?> veredito = const {};

  @override
  Future<RoomAnswer<BackTranslationVerdict>> finishBackTranslation(
    String sessionId, {
    required List<PlayedTake> playedByTake,
  }) async {
    final real = RoomRepository(
      client: MockClient((_) async => http.Response(jsonEncode(veredito), 200)),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(real.dispose);
    return real.finishBackTranslation(sessionId, playedByTake: playedByTake);
  }
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  test('um veredito que nomeia uma parte não ouvida sem recusa não põe '
      'parte nenhuma no ar', () async {
    final sala = _UmaSalaDeAntesDe19DeOutubro();
    final it = await umEnsaioContadoInteiro(
      partesDoEnsaio,
      numaSala: SalaHarness(room: sala),
    );
    sala.veredito = {
      'audio_url': falaDoVeredito,
      'checked': false,
      'unheard_take_ids': [it.partes[2].takeId],
      'findings_remaining': 0,
    };
    final tocadas = it.harness.playback.played.length;

    await pedirOVeredito(it);
    await settle();

    expect(
      it.harness.playback.played,
      hasLength(tocadas),
      reason:
          'a sala caía sozinha na parte nomeada, por um formato que nenhuma '
          'sala manda desde 19 de outubro; a dela recusa e não toca nada',
    );
    expect(it.estado.btClipRodando, isFalse);
  });

  test(
    'uma parte que acaba sem o player dizer nada não encolhe o colar',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      final terceira = it.partes[2].takeId!;
      it.harness.room
        ..verdictRefusal = CheckRefusal.partUnheard
        ..verdictFixedLine = 'P2'
        ..verdictUnheardTakeIds = [terceira]
        ..listeningUnheardTakeIds = [terceira];
      await pedirOVeredito(it);
      final tocadas = it.harness.playback.played.length;
      it.sala.ouvirGravacao();
      await theClipOpens(it.harness);

      it.harness.playback.length = null;
      it.harness.playback.at = Duration.zero;
      it.harness.playback.finishPlayback();
      await waitFor(
        'a segunda parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );

      expect(
        it.estado.btFimDasPartesMs,
        [10000, 18000, 30000],
        reason:
            'uma parte nunca tem zero milissegundo: um zero não é uma '
            'medida, é o player sem resposta, e escrevê-lo por cima do '
            'tamanho que a parte já mostrou encolhe o colar por baixo da '
            'equipe',
      );

      await ouvirAteOFim(it, partesDoEnsaio[1]);
      await waitFor(
        'a terceira parte entrar no ar',
        () => it.harness.playback.played.length == tocadas + 3,
      );
      await ouvirAteOFim(it, partesDoEnsaio[2]);
      it.harness.room
        ..verdictRefusal = null
        ..verdictUnheardTakeIds = const []
        ..listeningUnheardTakeIds = const [];
      await pedirOVeredito(it);

      expect(
        it.harness.room.playedByTakeSent.last.firstWhere(
          (parte) => parte['take_id'] == it.partes[0].takeId,
        )['clip_duration_ms'],
        10000,
        reason:
            'e o mesmo zero não pode entrar no relato: é ele que o '
            'servidor lê para decidir esta recusa, e uma parte ouvida '
            'inteira que se diz de zero milissegundo é o mesmo terminei '
            'recusado outra vez',
      );
    },
  );

  test(
    'a última audição segue sozinha pelas partes, do começo de cada uma',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      it.harness.room.verdictChecked = true;
      await pedirOVeredito(it);
      expect(
        it.estado.btPhase,
        BtPhase.conferida,
        reason:
            'o cenário é a passagem conferida — se não for, não mede a '
            'última audição',
      );

      final tocadas = it.harness.playback.played.length;
      it.sala.ouvirGravacao();
      await waitFor(
        'a primeira parte entrar no ar',
        () => it.harness.playback.played.length > tocadas,
      );

      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.playedFrom.last, Duration.zero);

      it.harness.playback.length = partesDoEnsaio[0];
      it.harness.playback.at = partesDoEnsaio[0];
      it.harness.playback.finishPlayback();
      await settle();

      expect(
        it.harness.playback.played.last,
        it.partes[1].path,
        reason: 'a primeira parte acabava calada, esperando um toque',
      );
      expect(
        it.harness.playback.playedFrom.last,
        Duration.zero,
        reason:
            'uma parte contada inteira tem o cursor no próprio fim, então '
            'atravessar para ela no cursor abre silêncio: a equipe ouvia a '
            'primeira parte e depois apertava duas vezes para nada. Não há '
            'mais tradução a fazer aqui, e o cursor não quer dizer nada numa '
            'passagem que a sala já conferiu',
      );
    },
  );

  test('um servidor que não manda o campo não recusa nada', () {
    final antigo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'findings_remaining': 0,
    });
    expect(antigo.unheardTakeIds, isEmpty);

    final nulo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'unheard_take_ids': null,
      'findings_remaining': 0,
    });
    expect(
      nulo.unheardTakeIds,
      isEmpty,
      reason:
          'uma recusa só existe quando o servidor a nomeia; lê-la de '
          'uma ausência é a inferência que a sala não faz',
    );

    final nomeadas = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'unheard_take_ids': ['t3', 't4'],
      'findings_remaining': 0,
      'refusal': 'PART_UNHEARD',
    });
    expect(nomeadas.unheardTakeIds, ['t3', 't4']);
  });

  test('uma recusa atrasada não muda nada nem chama ninguém', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro(
      tetoDaEspera: const Duration(seconds: 2),
    );
    final terceira = it.partes[2];
    final tocadas = it.harness.playback.played.length;

    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [terceira.takeId!];
    it.harness.voice.holdNextFetch();

    final aperto = it.sala.finishBackTranslation();
    await waitFor(
      'a sala desistir da espera',
      () => it.estado.btPhase != BtPhase.thinking,
    );
    it.harness.voice.finishHeldFetch();
    await aperto;

    expect(
      it.harness.playback.played.length,
      tocadas,
      reason:
          'a sala já desistiu desta espera: a resposta que chega depois é de '
          'uma pergunta que não está mais de pé',
    );
    expect(
      it.estado.needsPerson,
      isFalse,
      reason: 'uma espera sem fala que se esgota não chama ninguém',
    );
  });
}
