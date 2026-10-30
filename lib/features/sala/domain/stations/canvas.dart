part of '../station.dart';

/// The Station that holds the Conversation.
final class Canvas extends Station {
  const Canvas();

  @override
  SalaStage get stage => SalaStage.conversa;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    ThePlanOpened() => const Ensaio(step: EnsaioStep.plan),
    TheBackTranslationOpened() => const Retro(),
    TheSceneRehearsalOpened() => const SceneRehearsal(),
    TheSceneRehearsalLeft() => this,
    TheNecklaceClosed() => this,
    TheExternalCheckOpened() ||
    TheExternalCheckLeft() ||
    TheRecordingLeft() => this,
  };
}
