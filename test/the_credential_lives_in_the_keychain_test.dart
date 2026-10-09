import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/credential_vault.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _quickPoll = Duration(milliseconds: 20);

/// One answer every route's reader accepts — copied from `device_credential_test.dart`
/// so a case about the vault never turns into a case about response shapes.
String _anyAnswer() => jsonEncode({
  'session_id': 'sessao-1',
  'device_id': 'aparelho-1',
  'code': 'QHF-3M7K',
  'project_id': 'equipe-terena',
  'take_id': 'tomada-1',
  'credential': 'credencial-1',
});

Directory _tempHome() {
  final home = Directory.systemTemp.createTempSync('sala-cofre');
  addTearDown(() => home.deleteSync(recursive: true));
  return home;
}

File _ledgerFile(Directory home) => File('${home.path}/guardadas/vinculo.json');

LinkedTeam _ledger(Directory home, CredentialVault vault) =>
    LinkedTeam(home: () async => home, vault: vault);

ProviderContainer _tablet({
  required RoomRepository room,
  required LinkedTeam ledger,
  Duration? linkPoll,
}) {
  final outbox = _tempHome();
  return ProviderContainer(
    overrides: [
      roomRepositoryProvider.overrideWithValue(room),
      linkedTeamProvider.overrideWithValue(ledger),
      linkPollIntervalProvider.overrideWithValue(linkPoll),
      roomRetryBackoffProvider.overrideWithValue(const [_quickPoll]),
      takeUploadQueueProvider.overrideWithValue(
        TakeUploadQueue(room: room, home: () async => outbox),
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  group('the credential lives in the Keychain', () {
    test(
      'case 1 — collected, then presented from the vault, and the file is clean',
      () async {
        final home = _tempHome();
        final vault = FakeCredentialVault();
        final room = FakeRoom()
          ..presented = null
          ..linkedTo = const TeamLink(projectId: 'equipe-terena');
        final firstRun = _tablet(
          room: room,
          ledger: _ledger(home, vault),
          linkPoll: _quickPoll,
        );
        await firstRun.read(deviceLinkProvider.notifier).findTheTeam();
        await waitFor(
          'a credencial ser guardada no cofre',
          () async => await vault.read() != null,
        );
        firstRun.dispose();

        final seen = <http.BaseRequest>[];
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen.add(request);
            return http.Response(_anyAnswer(), 200);
          }),
        );
        addTearDown(repository.dispose);
        final nextRun = _tablet(room: repository, ledger: _ledger(home, vault));
        addTearDown(nextRun.dispose);

        await nextRun.read(deviceLinkProvider.notifier).findTheTeam();
        await repository.fetchState('sessao-1');

        expect(
          seen.single.headers['X-Device-Credential'],
          'credencial-1',
          reason:
              'uma segunda abertura sobre o mesmo cofre tem de apresentar a '
              'credencial que a primeira recolheu, sem pedi-la de novo ao servidor',
        );

        final onDisk =
            (jsonDecode(await _ledgerFile(home).readAsString()) as Map)
                .cast<String, Object?>();
        expect(
          onDisk.containsKey('credential'),
          isFalse,
          reason:
              'a credencial deixou o arquivo; ficar lá é o próprio defeito que '
              'esta mudança existe para fechar',
        );
      },
    );

    test('case 2 — nothing credential-shaped on disk', () async {
      final home = _tempHome();
      final vault = FakeCredentialVault();
      final room = FakeRoom()
        ..presented = null
        ..linkedTo = const TeamLink(projectId: 'equipe-terena');
      final container = _tablet(
        room: room,
        ledger: _ledger(home, vault),
        linkPoll: _quickPoll,
      );
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await waitFor(
        'a credencial ser guardada no cofre',
        () async => await vault.read() != null,
      );

      final credential = await vault.read();
      for (final entity in home.listSync(recursive: true)) {
        if (entity is! File) continue;
        expect(
          entity.readAsStringSync().contains(credential!),
          isFalse,
          reason:
              '${entity.path} não pode conter a credencial em nenhuma forma; '
              'um arquivo que a carrega é um arquivo que sobrevive a esta mudança '
              'com o mesmo defeito',
        );
      }
    });

    test('case 3 — an old file migrates once', () async {
      final home = _tempHome();
      final vault = FakeCredentialVault();
      await _ledgerFile(home).create(recursive: true);
      await _ledgerFile(home).writeAsString(
        jsonEncode({
          'device_id': 'aparelho-1',
          'project_id': 'equipe-terena',
          'credential': 'credencial-antiga',
        }),
      );

      final ledger = _ledger(home, vault);
      final firstRead = await ledger.read();

      expect(
        firstRead.credential,
        'credencial-antiga',
        reason:
            'a primeira abertura depois da mudança ainda tem de apresentar a '
            'credencial que o arquivo antigo guardava',
      );
      final afterMigration =
          (jsonDecode(await _ledgerFile(home).readAsString()) as Map)
              .cast<String, Object?>();
      expect(
        afterMigration.containsKey('credential'),
        isFalse,
        reason: 'a migração reescreve o arquivo sem a chave, uma vez',
      );
      expect(
        await vault.read(),
        'credencial-antiga',
        reason:
            'a credencial que saiu do arquivo tem de estar no cofre — senão a '
            'migração perdeu a única cópia',
      );

      final beforeSecondRead = await _ledgerFile(home).readAsString();
      final secondRead = await ledger.read();
      final afterSecondRead = await _ledgerFile(home).readAsString();

      expect(secondRead.credential, 'credencial-antiga');
      expect(
        afterSecondRead,
        beforeSecondRead,
        reason:
            'uma segunda abertura já migrada não tem mais nada a fazer no '
            'arquivo; tocá-lo de novo é a migração rodando mais de uma vez',
      );
    });

    test('case 4 — forgetting forgets both', () async {
      final home = _tempHome();
      final vault = FakeCredentialVault();
      final ledger = _ledger(home, vault);
      await ledger.rememberDevice('aparelho-1');
      await ledger.rememberTeam(const TeamLink(projectId: 'equipe-terena'));

      // Refused before any credential was ever collected: as `device_credential_test.dart`
      // notes, refusing after the credential is already held would prove nothing about
      // "sent back to a new code" that "never collected one" would not also show.
      final room = FakeRoom()
        ..presented = null
        ..linkedTo = const TeamLink(projectId: 'equipe-terena')
        ..refuseCredentialWith = const Refused(RefusalCode.credentialTaken);
      final container = _tablet(room: room, ledger: ledger);
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await waitFor(
        'um código novo aparecer',
        () => container.read(deviceLinkProvider).code != null,
      );

      expect(
        await vault.read(),
        isNull,
        reason:
            'um 403 encerra a única credencial que este aparelho teria como '
            'provar quem é; deixá-la no cofre é um vínculo que o servidor já negou',
      );
      final remembered = await ledger.read();
      expect(remembered.team, isNull);
      expect(remembered.credential, isNull);

      // The flow above can never reach _startOver with a credential already in the
      // vault — one present on read short-circuits collection before a 403 can arrive —
      // so forgetTheLink's own contract at the vault is checked directly here too.
      await vault.keep('credencial-2');
      await ledger.forgetTheLink();
      expect(
        await vault.read(),
        isNull,
        reason:
            'forgetTheLink apaga os dois — o arquivo e o cofre — mesmo quando '
            'o cofre chega com uma credencial que a rota pelo notifier acima '
            'nunca deixaria chegar até aqui',
      );
    });

    test(
      'case 6 — the production wrapper keeps with first_unlock_this_device',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final recorded = <String, Map<String, String>>{};
        FlutterSecureStoragePlatform.instance = _RecordingSecureStoragePlatform(
          recorded,
        );

        final vault = KeychainCredentialVault();
        await vault.keep('credencial-1', forDevice: 'aparelho-1');

        expect(
          recorded['credencial-1']?['accessibility'],
          'first_unlock_this_device',
          reason:
              'sem first_unlock_this_device, uma restauração do iCloud Keychain '
              'noutro aparelho herdaria a credencial que o servidor emitiu para este',
        );
      },
    );

    test(
      'case 7 — an unavailable vault does not collect nor delete, and looks again',
      () async {
        final home = _tempHome();
        final vault = FakeCredentialVault();
        await vault.keep('credencial-1');
        vault.unavailable = true;

        final ledger = _ledger(home, vault);
        await ledger.rememberDevice('aparelho-1');
        await ledger.rememberTeam(const TeamLink(projectId: 'equipe-terena'));

        final room = FakeRoom()
          ..presented = null
          ..linkedTo = const TeamLink(projectId: 'equipe-terena')
          ..refuseCredentialWith = const Refused(RefusalCode.credentialTaken);
        final container = _tablet(
          room: room,
          ledger: ledger,
          linkPoll: _quickPoll,
        );
        addTearDown(container.dispose);

        await container.read(deviceLinkProvider.notifier).findTheTeam();
        await settle();

        expect(
          room.credentialsCollected,
          isEmpty,
          reason:
              'o servidor já entregou esta credencial; pedir de novo com o '
              'cofre apenas trancado devolveria 403 e apagaria um vínculo que '
              'não está quebrado',
        );
        expect(
          room.codesAskedFor,
          isEmpty,
          reason:
              'nada foi esquecido; pedir um código novo é o que aconteceria '
              'se o vínculo tivesse sido apagado',
        );
        expect(
          container.read(deviceLinkProvider).team,
          isNull,
          reason:
              'ainda não sabemos se há credencial; o estado espera, em vez de '
              'se declarar vinculado sem ela ou pedir um código novo',
        );
        final onDisk =
            (jsonDecode(await _ledgerFile(home).readAsString()) as Map)
                .cast<String, Object?>();
        expect(onDisk['device_id'], 'aparelho-1');
        expect(onDisk['project_id'], 'equipe-terena');

        vault.unavailable = false;
        await waitFor(
          'a credencial ser apresentada depois que o cofre volta a responder',
          () => room.presented == 'credencial-1',
        );
        expect(
          room.credentialsCollected,
          isEmpty,
          reason:
              'a credencial que já estava no cofre nunca precisou ser pedida '
              'de novo ao servidor',
        );
      },
    );

    test(
      'case 8 — migration tolerates an unavailable vault; the file stays, and '
      'the next look migrates',
      () async {
        final home = _tempHome();
        final vault = FakeCredentialVault()..keepUnavailable = true;
        await _ledgerFile(home).create(recursive: true);
        await _ledgerFile(home).writeAsString(
          jsonEncode({
            'device_id': 'aparelho-1',
            'project_id': 'equipe-terena',
            'credential': 'credencial-antiga',
          }),
        );

        final ledger = _ledger(home, vault);
        final beforeMigration = await _ledgerFile(home).readAsString();
        final firstRead = await ledger.read();

        expect(
          firstRead.credentialUnavailable,
          isTrue,
          reason:
              'o cofre recusou a escrita; o resultado tem de dizer isso, não '
              'fingir que não há credencial nenhuma',
        );
        expect(firstRead.credential, isNull);
        final afterFailedMigration = await _ledgerFile(home).readAsString();
        expect(
          afterFailedMigration,
          beforeMigration,
          reason:
              'sem conseguir guardar no cofre, o arquivo tem de ficar como '
              'estava — apagar a credencial dali agora seria perdê-la de vez',
        );
        expect(
          await vault.read(),
          isNull,
          reason: 'a escrita falhou; o cofre continua vazio',
        );

        vault.keepUnavailable = false;
        final secondRead = await ledger.read();

        expect(
          secondRead.credential,
          'credencial-antiga',
          reason: 'com o cofre disponível de novo, a mesma abertura migra',
        );
        expect(secondRead.credentialUnavailable, isFalse);
        final afterMigration =
            (jsonDecode(await _ledgerFile(home).readAsString()) as Map)
                .cast<String, Object?>();
        expect(afterMigration.containsKey('credential'), isFalse);
        expect(await vault.read(), 'credencial-antiga');
      },
    );

    test('case 9 — a vault that cannot keep does not draw a second credential '
        'from the server', () async {
      final home = _tempHome();
      final vault = FakeCredentialVault()..keepUnavailable = true;
      final ledger = _ledger(home, vault);
      await ledger.rememberDevice('aparelho-1');
      await ledger.rememberTeam(const TeamLink(projectId: 'equipe-terena'));

      final room = FakeRoom()
        ..presented = null
        ..linkedTo = const TeamLink(projectId: 'equipe-terena');
      final container = _tablet(
        room: room,
        ledger: ledger,
        linkPoll: _quickPoll,
      );
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await waitFor(
        'a credencial ser apresentada mesmo sem conseguir gravar no cofre',
        () => room.presented == 'credencial-1',
      );
      await settle(const Duration(milliseconds: 100));
      await settle(const Duration(milliseconds: 100));

      expect(
        room.credentialsCollected,
        ['aparelho-1'],
        reason:
            'o servidor já entregou a única cópia; pedir de novo por causa '
            'de uma escrita que falhou no cofre desperdiça a credencial e '
            'arrisca um 403 sobre um vínculo que não está quebrado',
      );
      expect(
        container.read(deviceLinkProvider).code,
        isNull,
        reason:
            'nada foi apagado — a credencial está em memória, só a '
            'gravação no cofre falhou',
      );
      expect(
        container.read(deviceLinkProvider).team?.projectId,
        'equipe-terena',
      );

      vault.keepUnavailable = false;
      await waitFor(
        'a credencial finalmente ser guardada, quando o cofre volta a '
        'responder',
        () async => await vault.read() == 'credencial-1',
      );
      expect(room.credentialsCollected, [
        'aparelho-1',
      ], reason: 'guardar de novo não é pedir de novo');
    });
  });
}

/// Records the options `keep` writes with, without touching a real Keychain —
/// `flutter_secure_storage_platform_interface` exposes `.instance` as a settable seam
/// for exactly this.
class _RecordingSecureStoragePlatform extends FlutterSecureStoragePlatform {
  _RecordingSecureStoragePlatform(this.writtenOptions);

  final Map<String, Map<String, String>> writtenOptions;
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _data[key] = value;
    writtenOptions[value] = options;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _data[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _data.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => _data.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => _data;

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _data.clear();
}
