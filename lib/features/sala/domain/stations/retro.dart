part of '../station.dart';

/// The Back-translation, the one Station the Closing is reached from.
final class Retro extends Station {
  const Retro();

  @override
  SalaStage get stage => SalaStage.retro;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    ThePlanOpened() => this,
    TheBackTranslationOpened() || TheBackTranslationResumed() => const Retro(),
    TheSceneRehearsalOpened() || TheSceneRehearsalLeft() => this,
    TheNecklaceClosed() => const Fim(),
    TheExternalCheckOpened(:final version) => ChecagemExterna(version),
    TheExternalCheckLeft() => this,
  };
}
