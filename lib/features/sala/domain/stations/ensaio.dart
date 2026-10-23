part of '../station.dart';

/// The Rehearsal; the Closing is not reached from it, and the Back-translation is opened
/// from it only once every scene has its part. A reopened passage that had already
/// reached its telling-back resumes it whatever the Rehearsal weighed.
final class Ensaio extends Station {
  /// Whether every scene of the passage has its part, as the Rehearsal was last weighed.
  final bool everySceneHasItsPart;

  const Ensaio({this.everySceneHasItsPart = false});

  @override
  SalaStage get stage => SalaStage.ensaio;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() => everySceneHasItsPart ? const Retro() : this,
    TheBackTranslationResumed() => const Retro(),
    TheSceneRehearsalOpened() || TheSceneRehearsalLeft() => this,
    TheNecklaceClosed() => this,
    TheExternalCheckOpened() || TheExternalCheckLeft() => this,
  };
}
