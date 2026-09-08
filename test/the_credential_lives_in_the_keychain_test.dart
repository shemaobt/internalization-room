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
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';

import 'fakes.dart';

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
}) => ProviderContainer(
  overrides: [
    roomRepositoryProvider.overrideWithValue(room),
    linkedTeamProvider.overrideWithValue(ledger),
    linkPollIntervalProvider.overrideWithValue(linkPoll),
    roomRetryBackoffProvider.overrideWithValue(const [_quickPoll]),
  ],
);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  group('the credential lives in the Keychain', () {
    test(
      'case 1 — collected, then presented from the vault, and the file is clean',
      () async {
        final home = _tempHome();
        final vault = FakeCredentialVault();
        final room = FakeRoom()
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
        ..linkedTo = const TeamLink(projectId: 'equipe-terena')
        ..refuseCredentialWith = const CredentialTaken();
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
    });

    test('case 5 — the vault fake behaves like a store', () async {
      final vault = FakeCredentialVault();

      expect(await vault.read(), isNull);
      await vault.keep('credencial-1');
      expect(await vault.read(), 'credencial-1');
      await vault.forget();
      expect(await vault.read(), isNull);

      final another = FakeCredentialVault();
      await vault.keep('credencial-1');
      expect(
        await another.read(),
        isNull,
        reason:
            'dois cofres são dois aparelhos; um não pode ler o que o outro '
            'guardou',
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
        await vault.keep('credencial-1');

        expect(
          recorded['credencial-1']?['accessibility'],
          'first_unlock_this_device',
          reason:
              'sem first_unlock_this_device, uma restauração do iCloud Keychain '
              'noutro aparelho herdaria a credencial que o servidor emitiu para este',
        );
      },
    );
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
