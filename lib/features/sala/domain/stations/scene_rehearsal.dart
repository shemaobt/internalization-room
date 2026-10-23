part of '../station.dart';

/// The Scene rehearsal's screen, over the Canvas; never stored as a resume point.
final class SceneRehearsal extends Station {
  const SceneRehearsal();

  @override
  SalaStage get stage => SalaStage.cena;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    ThePlanOpened() => this,
    TheBackTranslationOpened() || TheBackTranslationResumed() => const Retro(),
    TheSceneRehearsalLeft() => const Canvas(),
    TheSceneRehearsalOpened() || TheNecklaceClosed() => this,
    TheExternalCheckOpened() || TheExternalCheckLeft() => this,
  };
}
