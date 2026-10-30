part of '../station.dart';

/// The Back-translation.
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
    TheBackTranslationOpened() => const Retro(),
    TheSceneRehearsalOpened() || TheSceneRehearsalLeft() => this,
    TheExternalCheckOpened(:final version) => ChecagemExterna(version),
    TheExternalCheckLeft() => this,
    TheRecordingLeft() => const Canvas(),
  };
}
