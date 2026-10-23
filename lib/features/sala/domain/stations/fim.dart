part of '../station.dart';

/// The Closing, reached only from the Back-translation.
final class Fim extends Station {
  const Fim();

  @override
  SalaStage get stage => SalaStage.fim;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() || TheBackTranslationResumed() => const Retro(),
    TheSceneRehearsalOpened() || TheSceneRehearsalLeft() => this,
    TheNecklaceClosed() => this,
    TheExternalCheckOpened() || TheExternalCheckLeft() => this,
  };
}
