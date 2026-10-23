part of '../station.dart';

/// The Station that holds the Choice.
final class Menu extends Station {
  const Menu();

  @override
  SalaStage get stage => SalaStage.escolha;

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
