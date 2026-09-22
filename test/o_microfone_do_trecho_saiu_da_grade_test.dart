import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/main.dart';

import 'a_pergunta_da_grade.dart' show byLabel, pumpToPergunta;
import 'fakes.dart';

const umaParteInteira = Duration(seconds: 30);
const continuarOEnsaioLabel = 'Continuar o ensaio';

/// Every target on the grid the team can put a finger on, in the order they are drawn.
///
/// Read off the buttons rather than off a list of labels this test also writes: what is
/// being held is that the screen offers these and nothing else, and a reading that only
/// looked for the ones it expected could not see a sixth.
List<String> alvosDaGrade(WidgetTester tester) => [
  for (final alvo in tester.widgetList<Semantics>(
    find.descendant(
      of: find.byType(OndeMoraGrade),
      matching: find.byType(Semantics),
    ),
  ))
    if (alvo.properties.button ?? false) alvo.properties.label ?? '',
];

Future<void> gravarUmaParte(
  WidgetTester tester,
  SalaSessionNotifier sala,
) async {
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> traduzirAParteInteira(
  WidgetTester tester,
  SalaHarness harness,
  SalaSessionNotifier sala,
) async {
  harness.playback.at = umaParteInteira;
  sala.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
}

/// A team that recorded the rehearsal in three parts and told every one of them back
/// whole, standing on the verdict's answer.
///
/// [lugar] is the place on the cord the analyst points at — 1 is the stretch of part 2,
/// and null is a missing the analyst could fit in no stretch at all.
Future<ProviderContainer> aPerguntaSobreAParteDois(
  WidgetTester tester,
  SalaHarness harness, {
  int? lugar = 1,
}) async {
  harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.missing
    ..verdictFindingPlace = lugar;
  harness.playback.length = umaParteInteira;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = container.read(salaSessionProvider.notifier);
  await sala.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  for (var parte = 0; parte < 3; parte++) {
    await gravarUmaParte(tester, sala);
  }
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  for (var parte = 0; parte < 3; parte++) {
    await traduzirAParteInteira(tester, harness, sala);
    if (parte < 2) {
      sala.ouvirGravacao();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// The mother tongue in the air, which is the only state the scissors is drawn in.
Future<void> ouvindoAMaterna(WidgetTester tester) async {
  await tester.tap(byLabel(ouvirMaternaLabel));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Let whatever is sounding reach its end, so the ceiling watching it is spent rather
/// than left running past the widget tree it belongs to.
Future<void> deixarOArSilenciar(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The gradient of the disc at the centre of the circle: the one drawing that carries one.
Gradient? discoDoCirculo(WidgetTester tester) {
  final pintados = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byType(Container),
        ),
      )
      .map((caixa) => caixa.decoration)
      .whereType<BoxDecoration>()
      .map((decoracao) => decoracao.gradient)
      .whereType<Gradient>()
      .toList();
  return pintados.isEmpty ? null : pintados.first;
}

/// Every colour the circle draws around the disc: the ring of the open microphone, the
/// rings closing in on it and their haloes.
Set<Color> emVoltaDoCirculo(WidgetTester tester) {
  final desenhadas = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byType(Container),
        ),
      )
      .map((caixa) => caixa.decoration)
      .whereType<BoxDecoration>();
  return {
    for (final decoracao in desenhadas) ...[
      if (decoracao.border != null) decoracao.border!.top.color,
      ...?decoracao.boxShadow?.map((sombra) => sombra.color),
    ],
  };
}

bool mesmoTom(Color uma, Color outra) =>
    uma.r == outra.r && uma.g == outra.g && uma.b == outra.b;

void main() {
  testWidgets('a grade oferece quatro gestos e a tesoura, e nada mais', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await aPerguntaSobreAParteDois(tester, harness);

    await ouvindoAMaterna(tester);

    expect(
      alvosDaGrade(tester).toSet(),
      {
        ouvirMaternaLabel,
        ouvirRetroLabel,
        micParteLabel,
        micRetroLabel,
        cortarTrechoLabel,
      },
      reason:
          'a pergunta é entre duas vozes: ouvir cada uma, pedir a cada uma '
          'que fale de novo, e cortar o que está no ar. O microfone por trecho '
          'da materna era um sexto alvo e saiu da tela',
    );
    expect(
      alvosDaGrade(tester),
      hasLength(5),
      reason:
          'contado, e não só listado: um alvo repetido é um dedo que cai '
          'no lugar errado, e o conjunto acima não o veria',
    );

    await deixarOArSilenciar(tester, harness);
  });

  testWidgets('os dois tocadores da grade põem cada voz no ar', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aPerguntaSobreAParteDois(tester, harness);
    final apontado = container.read(salaSessionProvider).btFindingTrecho!;
    expect(
      apontado.parte,
      1,
      reason:
          'o achado aponta um trecho da parte 2, que é o que estes casos '
          'medem',
    );

    await ouvindoAMaterna(tester);

    expect(
      harness.playback.played.last,
      container.read(salaSessionProvider).partes[1].path,
      reason:
          'o tocador de madeira põe no ar a gravação da equipe, que é a '
          'parte onde o trecho mora',
    );

    await tester.tap(byLabel(ouvirMaternaLabel));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(byLabel(ouvirRetroLabel));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.playback.played.last,
      apontado.retroPath,
      reason:
          'e o tocador azul põe no ar a tradução em português, que é a '
          'voz que viaja até o analista',
    );

    await deixarOArSilenciar(tester, harness);
  });

  testWidgets('a tesoura da grade divide o trecho que está no ar', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aPerguntaSobreAParteDois(tester, harness);
    final antes = container.read(salaSessionProvider).btTrechos.length;

    await ouvindoAMaterna(tester);
    harness.playback.at = const Duration(seconds: 4);
    await tester.tap(byLabel(cortarTrechoLabel));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(salaSessionProvider).btTrechos,
      hasLength(antes + 1),
      reason:
          'o corte faz duas unidades de uma, e o colar ganha a faixa da '
          'metade nova',
    );
  });

  testWidgets('o microfone azul da grade manda a gravação com o replace', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aPerguntaSobreAParteDois(tester, harness);
    final sala = container.read(salaSessionProvider.notifier);
    final apontado = container.read(salaSessionProvider).btFindingSegmentId;
    final vizinhos = [
      for (final trecho in container.read(salaSessionProvider).btTrechos)
        if (trecho.segmentId != apontado)
          '${trecho.segmentId}:${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
    ];

    await tester.tap(byLabel(micRetroLabel));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.capturing,
      reason: 'o microfone azul abre a captura da frase, sem sair da retro',
    );
    expect(
      container.read(salaSessionProvider).btEsperandoConserto,
      isNull,
      reason:
          'a faixa do trecho apontado enche ao escolher: a promessa do '
          'conserto é feita aqui, antes de qualquer coisa ir para a sala',
    );

    sala.retroTap();
    await letTheRehearsalReachTheRoom(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      harness.room.replacesComArquivo,
      [harness.recorder.lastPath],
      reason:
          'o caminho curto conta a frase de novo sobre a gravação que '
          'não se mexeu, e é essa gravação que sobe com o replace',
    );
    expect(
      [
        for (final trecho in container.read(salaSessionProvider).btTrechos)
          if (trecho.segmentId != apontado &&
              !trecho.segmentId!.startsWith('$apontado-'))
            '${trecho.segmentId}:${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
      ],
      vizinhos,
      reason:
          'o conserto é de um trecho só: as faixas dos vizinhos ficam onde '
          'estavam e com o nome que tinham',
    );
  });

  testWidgets(
    'o microfone de madeira da grade grava a parte de novo no lugar',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await aPerguntaSobreAParteDois(tester, harness);
      final sala = container.read(salaSessionProvider.notifier);
      final antes = container.read(salaSessionProvider).partes;
      expect(antes, hasLength(3));

      await tester.tap(byLabel(micParteLabel));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason:
            'a voz de madeira é a parte inteira: o que ela abre é o ensaio, '
            'onde a parte se grava outra vez',
      );

      await gravarUmaParte(tester, sala);

      final agora = container.read(salaSessionProvider).partes;
      expect(
        agora,
        hasLength(3),
        reason:
            'a parte gravada de novo fica no lugar da parte 2: a fila do '
            'ensaio não cresce',
      );
      expect(agora[1].path, isNot(antes[1].path));
      expect(
        [agora[0].path, agora[2].path],
        [antes[0].path, antes[2].path],
        reason: 'e as vizinhas ficam com a gravação que já tinham',
      );
    },
  );

  testWidgets('a saída para gravar mais diz continuar o ensaio', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aPerguntaSobreAParteDois(
      tester,
      harness,
      lugar: null,
    );
    final antes = container.read(salaSessionProvider);
    expect(
      antes.btFindingTrecho,
      isNull,
      reason:
          'a falta não coube em trecho nenhum: a pergunta não é posta e '
          'a tela é a das saídas',
    );

    expect(
      byLabel(continuarOEnsaioLabel),
      findsOneWidget,
      reason:
          'esta saída acrescenta ao ensaio, e o nome dela tem de dizer '
          'isso: "gravar esta parte de novo" era o nome do gesto oposto',
    );
    expect(
      byLabel('Gravar esta parte de novo'),
      findsNothing,
      reason: 'dois rótulos que só diferem pelo rabo nomeavam atos opostos',
    );

    await tester.tap(byLabel(continuarOEnsaioLabel));
    await tester.pump(const Duration(milliseconds: 400));

    final depois = container.read(salaSessionProvider);
    expect(depois.stage, SalaStage.ensaio);
    expect(
      [for (final take in depois.keptTakes) take.takeId],
      [for (final take in antes.keptTakes) take.takeId],
      reason:
          'o fim da história é o que falta gravar; o que já foi gravado fica',
    );
    expect(
      [for (final trecho in depois.btTrechos) trecho.segmentId],
      [for (final trecho in antes.btTrechos) trecho.segmentId],
      reason: 'e os trechos já contados e certos continuam contados',
    );
  });

  testWidgets('o caminho curto fica curto', (tester) async {
    final (container, harness) = await pumpToPergunta(tester);
    // The rehearsal's own take is already in there from the setup; what this scenario is
    // about is whether the short way adds another one.
    harness.room.takesKept.clear();
    harness.playback.measurements.clear();

    await tester.tap(byLabel(micRetroLabel));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      harness.room.takesKept.where((k) => k.startsWith('ensaio')),
      isEmpty,
      reason: 'escolher só a tradução não grava voz nova em língua materna',
    );
    expect(
      harness.playback.measurements,
      isEmpty,
      reason: 'nem mede duração de gravação nenhuma — não há gravação nova',
    );
  });

  testWidgets('o círculo não é madeira ao consertar', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aPerguntaSobreAParteDois(tester, harness);

    expect(
      discoDoCirculo(tester),
      isNot(BeadStyles.wood),
      reason:
          'na pergunta o círculo é a voz da sala, e não a tinta de uma '
          'estação que saiu',
    );

    await tester.tap(byLabel(micRetroLabel));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason: 'o microfone tem de estar mesmo aberto para medir a cor dele',
    );

    expect(
      discoDoCirculo(tester),
      BeadStyles.azul,
      reason:
          'o microfone aberto na retro é sempre o da ponte: com a '
          'estação da materna fora, não há segunda tinta a distinguir',
    );
    expect(
      [
        for (final tom in emVoltaDoCirculo(tester))
          if (mesmoTom(tom, ShemaBrand.wood) ||
              mesmoTom(tom, ShemaBrand.woodLo))
            tom,
      ],
      isEmpty,
      reason: 'nem no anel, nem nos anéis que se fecham, nem nos halos',
    );
  });
}
