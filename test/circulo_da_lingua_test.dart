import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'caminho_longo_test.dart'
    show byLabel, micMaterna, micRetro, notifier, pumpToPergunta;
import 'fakes.dart' show letTheRehearsalReachTheRoom;

/// The gradient the disc at the centre of the circle is painted with.
///
/// The rings around it carry borders and no gradient, so the disc is the only one, and
/// asking for exactly one is what keeps this from reading a ripple by mistake.
Gradient? _disco(WidgetTester tester) {
  final pintados = tester
      .widgetList<Container>(find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ))
      .map((caixa) => caixa.decoration)
      .whereType<BoxDecoration>()
      .map((decoracao) => decoracao.gradient)
      .whereType<Gradient>()
      .toList();
  expect(pintados, hasLength(lessThan(2)),
      reason: 'o corpo é o único desenho do círculo com gradiente; com dois '
          'este ajudante não sabe qual deles é o disco, e um StateError cru '
          'não diria isso a quem vier depois');
  return pintados.isEmpty ? null : pintados.first;
}

/// Every colour the circle paints that is not the disc's own fill: the ring of the open
/// microphone, the rings closing in, and the haloes under all of them.
///
/// They fade in and out, so each one is drawn at whatever alpha its frame asks for. What
/// is being asked here is which tone was chosen, and alpha is no part of that.
Set<Color> _emVolta(WidgetTester tester) {
  final desenhadas = tester
      .widgetList<Container>(find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ))
      .map((caixa) => caixa.decoration)
      .whereType<BoxDecoration>();
  return {
    for (final decoracao in desenhadas) ...[
      if (decoracao.border != null) decoracao.border!.top.color,
      ...?decoracao.boxShadow?.map((sombra) => sombra.color),
    ],
  };
}

bool _mesmoTom(Color uma, Color outra) =>
    uma.r == outra.r && uma.g == outra.g && uma.b == outra.b;

Future<void> _pumpCirculo(
  WidgetTester tester,
  VoiceState voice,
  ThemeData theme, {
  bool peerCue = false,
  bool warning = false,
}) =>
    tester.pumpWidget(MaterialApp(
      key: ValueKey('$voice-$peerCue-$warning-${theme.brightness}'),
      theme: theme,
      home: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: 150,
            voice: voice,
            peerCue: peerCue,
            warning: warning,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ));

/// Whether the circle drew one of the glyphs a halted state wears — the userCheck,
/// the cloudOff/serverOff, or the micOff — the mark a warning must never cover.
bool _haltedGlyph(WidgetTester tester) => tester
    .widgetList<Icon>(find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Icon),
    ))
    .isNotEmpty;

/// One pumped frame, with what the room was doing on it.
class _Quadro {
  final BtPhase fase;
  final VoiceState voz;
  final Gradient? disco;

  const _Quadro(this.fase, this.voz, this.disco);

  @override
  String toString() => '${fase.name}/${voz.name}: $disco';
}

void main() {
  testWidgets('gravando a língua materna, o círculo é âmbar', (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));
    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 200));

    final estado = container.read(salaSessionProvider);
    expect(estado.btPhase, BtPhase.gravandoMaterna);
    expect(estado.voice, VoiceState.listening,
        reason: 'sem o microfone aberto não há gravação para colorir, e este '
            'teste estaria olhando outra tela');

    expect(_disco(tester), BeadStyles.wood,
        reason: 'as duas gravações da correção passam pelo mesmo '
            'VoiceState.listening, e o círculo só lia a voz: a equipe recebia '
            'o mesmo azul para falar na língua materna e para contar na '
            'língua-ponte, sem nada na tela dizendo em qual delas falar agora');
  });

  testWidgets('gravando a retrotradução, o círculo é azul', (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micRetro));
    await tester.pump(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    expect(estado.btPhase, BtPhase.capturing);
    expect(estado.voice, VoiceState.listening);

    expect(_disco(tester), BeadStyles.azul,
        reason: 'esta é a metade que já estava certa: azul é a cor do contar '
            'em português, e distinguir a materna não pode custá-la');
  });

  testWidgets('a cor vira âmbar e só depois azul, na sequência real',
      (tester) async {
    final container = await pumpToPergunta(tester);
    final trilha = <_Quadro>[];

    Future<void> registrar(int quadros) async {
      for (var frame = 0; frame < quadros; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        final estado = container.read(salaSessionProvider);
        trilha.add(_Quadro(estado.btPhase, estado.voice, _disco(tester)));
      }
    }

    // A equipe escolhe regravar a voz, grava a língua materna, e a sala emenda
    // sozinha o contar daquele trecho em português. São as duas estações, uma
    // atrás da outra, do jeito que a equipe as percorre. Os quadros contados
    // entre um toque e o outro são a espera: a escolha chegar à tela, o
    // microfone da materna ficar aberto por um punhado de quadros, e a
    // substituição no servidor — que é trabalho de disco de verdade, e por isso
    // precisa de `letTheRehearsalReachTheRoom` no meio.
    await tester.tap(byLabel(micMaterna));
    await registrar(3);
    notifier(container).retroTap();
    await registrar(6);
    notifier(container).retroTap();
    await registrar(3);
    await letTheRehearsalReachTheRoom(tester);
    await registrar(6);

    final materna = trilha.where((quadro) =>
        quadro.fase == BtPhase.gravandoMaterna &&
        quadro.voz == VoiceState.listening);
    final ponte = trilha.where((quadro) =>
        quadro.fase == BtPhase.capturing &&
        quadro.voz == VoiceState.listening);

    expect(materna, isNotEmpty,
        reason: 'o passeio precisa mesmo abrir o microfone na língua materna, '
            'senão não há o que olhar');
    expect(ponte, isNotEmpty,
        reason: 'e precisa mesmo chegar à segunda estação, que é onde a troca '
            'de cor tem de ter acontecido');

    expect(materna.map((quadro) => quadro.disco).toSet(), {BeadStyles.wood},
        reason: 'âmbar do primeiro ao último quadro da materna — uma troca '
            'que chega tarde deixa a equipe começando a falar no azul');
    expect(ponte.map((quadro) => quadro.disco).toSet(), {BeadStyles.azul},
        reason: 'e azul do primeiro ao último quadro da ponte — uma troca que '
            'chega cedo demais colore de âmbar o contar em português');

    final primeiroAmbar =
        trilha.indexWhere((quadro) => quadro.disco == BeadStyles.wood);
    final primeiroAzul =
        trilha.indexWhere((quadro) => quadro.disco == BeadStyles.azul);
    expect(primeiroAmbar, greaterThanOrEqualTo(0));
    expect(primeiroAzul, greaterThan(primeiroAmbar),
        reason: 'a ordem é o que a equipe lê: primeiro a voz de vocês, depois '
            'o contar. Olhar os dois estados isolados não pegaria isto');

    expect(
        trilha
            .where((quadro) => quadro.fase == BtPhase.gravandoMaterna)
            .map((quadro) => quadro.disco),
        everyElement(isNot(BeadStyles.azul)),
        reason: 'nenhum quadro azul enquanto a estação é a língua materna, '
            'nem o convite antes do microfone abrir');
  });

  testWidgets('tudo que o círculo desenha é madeira enquanto a voz é a materna',
      (tester) async {
    final container = await pumpToPergunta(tester);

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));
    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.gravandoMaterna);

    // O halo do clipe é irmão do círculo, não filho dele, e é azul: fora deste
    // finder. Ele não desenha aqui porque cortar o trecho parou o tocador e
    // escolher a voz limpou o que restava — o que nada mais no conjunto prende.
    final sessao = container.read(salaSessionProvider);
    expect(sessao.btClipRodando || sessao.btTrechoTocando, isFalse,
        reason: 'com o clipe correndo haveria um anel azul em volta do círculo '
            'que este teste não alcança, e a tela mentiria de novo');

    final emVolta = _emVolta(tester);
    expect(emVolta, isNotEmpty,
        reason: 'escutando, o círculo desenha o anel do microfone aberto, os '
            'anéis que se fecham e os haloes deles — se não desenha, este '
            'teste não olha nada');
    for (final cor in emVolta) {
      expect(
          [ShemaBrand.woodHi, ShemaBrand.wood, ShemaBrand.woodLo]
              .any((tom) => _mesmoTom(cor, tom)),
          isTrue,
          reason: 'um disco âmbar sob anéis e haloes azuis continua sendo um '
              'círculo azul para quem olha do chão. Dizer só "nada é azul" '
              'deixaria passar um anel verde, então o que se pede é a madeira');
    }
  });

  testWidgets('os outros estados do círculo ficam com as cores de antes',
      (tester) async {
    for (final tema in [
      (AppTheme.light, SalaColors.light),
      (AppTheme.dark, SalaColors.dark),
    ]) {
      final (theme, colors) = tema;
      final deAntes = {
        VoiceState.invite: BeadStyles.telha(colors),
        VoiceState.speaking: BeadStyles.telha(colors),
        VoiceState.listening: BeadStyles.azul,
        VoiceState.thinking: BeadStyles.clay(colors, 0),
        VoiceState.done: BeadStyles.verde,
        VoiceState.needsPerson: BeadStyles.clay(colors, 0),
        VoiceState.offline: BeadStyles.clay(colors, 0),
        VoiceState.blocked: BeadStyles.clay(colors, 0),
      };

      for (final entrada in deAntes.entries) {
        // Sem quadro nenhum depois de montar: pensando respira, e o barro é
        // clareado pela respiração. O gradiente exato só existe em t = 0, que é
        // o quadro que `pumpWidget` desenha. Um `pump` a mais aqui e a linha do
        // pensando falha por causa da respiração, não por causa de cor.
        await _pumpCirculo(tester, entrada.key, theme);
        expect(_disco(tester), entrada.value,
            reason: 'um switch mexido vaza pelos ramos vizinhos, e '
                '${entrada.key.name} não tem nada a ver com a língua materna');
      }

      await _pumpCirculo(tester, VoiceState.invite, theme, peerCue: true);
      expect(_disco(tester), BeadStyles.azul,
          reason: 'a fala da equipe é azul e continua azul');
    }
  });

  // Os dois rótulos da regravação também são lidos por
  // `caminho_longo_test.dart`, no teste que prova o que cada toque faz. Aqui
  // eles são o critério de aceite desta mudança: uma cor nova não pode custar a
  // leitura em voz alta da tela, e a fase apontada, que aquele teste não cobre,
  // entra junto.
  testWidgets('o rótulo lido em voz alta continua distinguindo as fases',
      (tester) async {
    final container = await pumpToPergunta(tester);

    expect(byLabel('Ouvir a pergunta de novo'), findsOneWidget);

    await tester.tap(byLabel(micMaterna));
    await tester.pump(const Duration(milliseconds: 300));
    expect(byLabel('Gravar este trecho'), findsOneWidget,
        reason: 'escolhida a voz e o microfone ainda fechado, o círculo é o '
            'convite para gravar');

    notifier(container).retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    expect(byLabel('Tocar ao terminar a gravação'), findsOneWidget,
        reason: 'gravando, ele é o botão de parar — uma cor nova não pode '
            'custar a leitura em voz alta da tela');
  });

  testWidgets(
      'uma parada bloqueante nunca é verde, mesmo com o aviso ligado',
      (tester) async {
    await _pumpCirculo(tester, VoiceState.needsPerson, AppTheme.light,
        warning: true);

    expect(_disco(tester), isNot(BeadStyles.verde),
        reason: 'uma parada de verdade pede uma pessoa e recusa o gesto; um '
            'aviso de segundos atrás não desfaz isso, então o disco continua '
            'sendo o do corpo parado');
    expect(_haltedGlyph(tester), isTrue,
        reason: 'e o corpo parado continua desenhando o seu ícone — o aviso '
            'nunca chega a competir com uma parada que já está na tela');
  });

  testWidgets('o disco só fica verde com o aviso ligado e a voz solta',
      (tester) async {
    const halted = {VoiceState.needsPerson, VoiceState.offline};
    const vozes = [
      VoiceState.invite,
      VoiceState.listening,
      VoiceState.speaking,
      VoiceState.done,
      VoiceState.needsPerson,
      VoiceState.offline,
    ];

    for (final voz in vozes) {
      for (final aviso in [true, false]) {
        await _pumpCirculo(tester, voz, AppTheme.light, warning: aviso);
        final verde = aviso && !halted.contains(voz) || voz == VoiceState.done;

        expect(_disco(tester) == BeadStyles.verde, verde,
            reason: verde
                ? '${voz.name} com aviso=$aviso tinha de acender o disco de '
                    '"pronto" — é o único sinal que o aviso tem, já que a sala '
                    'não fala'
                : '${voz.name} com aviso=$aviso não pode acender o disco de '
                    '"pronto": ou o aviso está desligado, ou a voz já é uma '
                    'parada que o aviso não supera');

        if (halted.contains(voz)) {
          expect(_haltedGlyph(tester), isTrue,
              reason: '${voz.name} sempre desenha o seu ícone, com aviso ou '
                  'sem ele');
        }
      }
    }
  });

  testWidgets(
      'o microfone bloqueado também vence o aviso — a terceira parada da lista',
      (tester) async {
    await _pumpCirculo(tester, VoiceState.blocked, AppTheme.light,
        warning: true);

    expect(_disco(tester), isNot(BeadStyles.verde),
        reason: '_halted lista needsPerson, offline e blocked juntos; a '
            'matriz acima só cobre os dois primeiros, e um terceiro estado '
            'parado que a lista promete e o teste não olha é onde uma '
            'reordenação futura do corpo do círculo passaria despercebida');
    expect(_haltedGlyph(tester), isTrue);
  });

  // Caso 6 (Emenda 1, 07/09): a deixa ao vivo da equipe ("é sua vez de falar")
  // é um sinal de turno, e o aviso é uma notícia de fundo — a deixa vence o
  // verde da mesma forma que uma voz parada vence.
  testWidgets('a deixa da equipe não some atrás de um aviso', (tester) async {
    for (final aviso in [true, false]) {
      await _pumpCirculo(tester, VoiceState.invite, AppTheme.light,
          peerCue: true, warning: aviso);

      expect(find.byIcon(LucideIcons.users), findsOneWidget,
          reason: 'aviso=$aviso: a marca da deixa ao vivo não é negociável — '
              'sumir atrás de um aviso de fundo tira da equipe o único sinal '
              'de que é a vez dela de falar');
    }
  });
}
