import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/dev/dev_skip_bar.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/convite_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;

const _unclaimed = RememberedLink();

void _devEnv() {
  dotenv.testLoad(
    fileInput:
        'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
  );
  addTearDown(() => dotenv.testLoad(fileInput: ''));
}

void main() {
  testWidgets(
    'a tablet nobody has linked yet shows a code and nothing else to read',
    (tester) async {
      final harness = SalaHarness(linkedAs: _unclaimed);
      await pumpSala(tester, harness);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CodigoView), findsOneWidget);
      expect(find.text('QHF-3M7K'), findsOneWidget);
      expect(
        find.byType(Text),
        findsOneWidget,
        reason:
            'o código é a única palavra que a sala já mostrou; qualquer outra '
            'na mesma tela é uma que a equipe não sabe ler',
      );
      expect(
        find.byType(EditableText),
        findsNothing,
        reason:
            'quem digita é o facilitador, na Mesa — o aparelho mostra e nunca pede',
      );
    },
  );

  testWidgets('a tablet still waiting for its code offers the room no way in', (
    tester,
  ) async {
    final harness = SalaHarness(linkedAs: _unclaimed)..room.holdNextCode();
    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(ConviteView),
      findsNothing,
      reason:
          'entre o pedido e a resposta a tela caía no convite, e um toque ali abria '
          'sessão com a chave compartilhada — exatamente o que o vínculo existe para tirar',
    );
    expect(find.byType(EditableText), findsNothing);

    harness.room.finishHeldCode();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CodigoView), findsOneWidget);
  });

  testWidgets('a tablet that was already linked never sees the code screen', (
    tester,
  ) async {
    final harness = SalaHarness();
    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CodigoView), findsNothing);
    expect(
      harness.room.codesAskedFor,
      isEmpty,
      reason:
          'um aparelho já vinculado que pede código volta a mostrar a tela da '
          'instalação para uma equipe que já está trabalhando',
    );
  });

  test(
    'a code that ran out is replaced with nobody touching the tablet',
    () async {
      final harness =
          SalaHarness(
              linkedAs: _unclaimed,
              linkPoll: const Duration(milliseconds: 300),
            )
            ..room.claimCodes = const ['QHF-3M7K', 'WKD-2QP4']
            ..room.claimCodeLife = Duration.zero;
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await settle();
      expect(container.read(deviceLinkProvider).code?.code, 'QHF-3M7K');

      await waitFor(
        'o código vencido ser trocado',
        () => container.read(deviceLinkProvider).code?.code == 'WKD-2QP4',
      );

      expect(
        container.read(deviceLinkProvider).code?.code,
        'WKD-2QP4',
        reason:
            'um código vencido seguia na tela e o facilitador digitava um que a '
            'Mesa já não aceitava',
      );
    },
  );

  test('a link it cannot read is never written over', () async {
    final home = Directory.systemTemp.createTempSync('sala-vinculo');
    addTearDown(() => home.deleteSync(recursive: true));
    final ledger = LinkedTeam(home: () async => home);
    await ledger.rememberTeam(const TeamLink(projectId: 'equipe-terena'));

    final file = File('${home.path}/guardadas/vinculo.json');
    await file.writeAsString('{"project_id": "equipe-ter');
    await ledger.rememberDevice('aparelho-2');

    expect(
      await file.readAsString(),
      '{"project_id": "equipe-ter',
      reason:
          'a leitura falhava, virava vínculo vazio, e o próximo pedido de código '
          'gravava um registro sem equipe — a tela de instalação voltava para uma '
          'sala que já estava trabalhando',
    );
  });

  test(
    'a tablet reopened after the claim landed reads it, it does not draw over it',
    () async {
      final harness = SalaHarness(
        linkedAs: const RememberedLink(deviceId: 'aparelho-1'),
        linkPoll: const Duration(milliseconds: 300),
      )..room.linkedTo = const TeamLink(projectId: 'equipe-terena');
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await waitFor(
        'o tablet ficar ligado à equipe',
        () => container.read(deviceLinkProvider).linked,
      );

      expect(
        container.read(deviceLinkProvider).team?.projectId,
        'equipe-terena',
      );
      expect(
        harness.room.codesAskedFor,
        isEmpty,
        reason:
            'o aparelho pedia código antes de ler o vínculo, o servidor respondia um '
            'aparelho novo para um id já vinculado, e a equipe que o facilitador acabara '
            'de escolher ficava numa linha que ninguém mais lê',
      );
    },
  );

  test('a code that ran out after it was spent is read, not redrawn', () async {
    final harness = SalaHarness(
      linkedAs: _unclaimed,
      linkPoll: const Duration(milliseconds: 100),
    )..room.claimCodeLife = Duration.zero;
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await settle();
    harness.room.linkedTo = const TeamLink(projectId: 'equipe-terena');
    final drawnBefore = harness.room.codesAskedFor.length;

    await waitFor(
      'o tablet ficar ligado à equipe',
      () => container.read(deviceLinkProvider).linked,
    );

    expect(container.read(deviceLinkProvider).team?.projectId, 'equipe-terena');
    expect(
      harness.room.codesAskedFor.length,
      drawnBefore,
      reason:
          'o vencimento era checado antes da leitura, então uma escolha feita nos '
          'últimos segundos do código era descartada pelo tique seguinte',
    );
  });

  test(
    'a debug build told to skip the phases is linked without asking the room',
    () async {
      _devEnv();
      final harness = SalaHarness(linkedAs: _unclaimed);
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await settle();

      expect(container.read(deviceLinkProvider).linked, isTrue);
      expect(
        harness.room.codesAskedFor,
        isEmpty,
        reason:
            'sem isso a sala de desenvolvimento só abre depois que alguém vincula '
            'o aparelho pela Mesa, que é justamente o que ainda não roda local',
      );
      expect(
        harness.vinculo.remembered.team,
        isNull,
        reason:
            'um vínculo inventado gravado em disco sobrevive a desligar o '
            'sinalizador, e o aparelho passa a mentir sobre a equipe para sempre',
      );
    },
  );

  test(
    'a release build shows the code even when the .env says to skip',
    () async {
      _devEnv();
      final harness = SalaHarness(linkedAs: _unclaimed);
      final container = ProviderContainer(
        overrides: [
          ...harness.overrides,
          debugBuildProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await settle();

      expect(
        container.read(deviceLinkProvider).code,
        isNotNull,
        reason:
            'o build de release empacota o .env que estiver na árvore de quem '
            'compila, então o sinalizador sozinho deixaria um tablet entrar na sala '
            'sem nunca ter sido vinculado',
      );
    },
  );

  test(
    'a tablet put down mid-question is a room closing, not a room breaking',
    () async {
      final harness = SalaHarness(linkedAs: _unclaimed)..room.holdNextCode();
      final container = harness.container();
      unawaited(container.read(deviceLinkProvider.notifier).findTheTeam());
      await settle();

      container.dispose();
      harness.room.finishHeldCode();
      await settle();

      expect(
        harness.vinculo.remembered.deviceId,
        isNull,
        reason:
            'a resposta chegava depois do container fechado, lia um provider morto '
            'e derrubava a chamada inteira com Bad state',
      );
    },
  );

  test(
    'a tablet learns the team that spent its code, with nobody touching it',
    () async {
      final harness = SalaHarness(
        linkedAs: _unclaimed,
        linkPoll: const Duration(milliseconds: 20),
      );
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await settle();
      expect(container.read(deviceLinkProvider).code, isNotNull);

      harness.room.linkedTo = const TeamLink(
        projectId: 'equipe-terena',
        label: 'prateleira',
      );
      await waitFor(
        'o tablet ficar ligado à equipe',
        () => container.read(deviceLinkProvider).linked,
      );

      expect(
        container.read(deviceLinkProvider).team?.projectId,
        'equipe-terena',
      );
      expect(
        harness.vinculo.remembered.team?.projectId,
        'equipe-terena',
        reason:
            'o vínculo só vivia na memória, então o aparelho reaberto pedia um '
            'código novo e mostrava a tela de instalação para a equipe',
      );
    },
  );

  test(
    'the tablet keeps the device it was given, so the code on the table stays its own',
    () async {
      final harness = SalaHarness(
        linkedAs: _unclaimed,
        linkPoll: const Duration(milliseconds: 20),
      )..room.claimCodeLife = Duration.zero;
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(deviceLinkProvider.notifier).findTheTeam();
      await waitFor(
        'um segundo código ser pedido',
        () => harness.room.codesAskedFor.length > 1,
      );

      expect(harness.room.codesAskedFor.first, isNull);
      expect(
        harness.room.codesAskedFor[1],
        'aparelho-1',
        reason:
            'cada pedido sem o aparelho abandonava a linha anterior, e o código '
            'que o facilitador tinha anotado deixava de existir',
      );
    },
  );
}
