part of '../station.dart';

/// The recording home, or the Ensaio Final plan the orange dot opens over a passage with no
/// take yet.
enum EnsaioStep { home, plan }

/// The Rehearsal; the Closing is not reached from it, and the Back-translation is opened
/// from it only once every scene has its part, every part is on the tablet and none waits
/// in the Outbox. A reopened passage that had already
/// reached its telling-back resumes it whatever the Rehearsal weighed.
final class Ensaio extends Station {
  /// Whether every scene of the passage has its part, as the Rehearsal was last weighed.
  final bool everySceneHasItsPart;

  /// Whether every part is on the tablet, as the Rehearsal was last weighed.
  final bool everyPartIsHere;

  final bool everyPartIsSent;

  final EnsaioStep step;

  const Ensaio({
    this.everySceneHasItsPart = false,
    this.everyPartIsHere = true,
    this.everyPartIsSent = true,
    this.step = EnsaioStep.home,
  });

  @override
  SalaStage get stage => SalaStage.ensaio;

  @override
  bool operator ==(Object other) => other is Ensaio && other.step == step;

  @override
  int get hashCode => step.hashCode;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    ThePlanOpened() =>
      step == EnsaioStep.home
          ? Ensaio(
              step: EnsaioStep.plan,
              everySceneHasItsPart: everySceneHasItsPart,
            )
          : this,
    TheBackTranslationOpened() =>
      everySceneHasItsPart &&
              everyPartIsHere &&
              everyPartIsSent &&
              step == EnsaioStep.home
          ? const Retro()
          : this,
    TheBackTranslationResumed() => const Retro(),
    TheSceneRehearsalOpened() => const SceneRehearsal(),
    TheSceneRehearsalLeft() => this,
    TheNecklaceClosed() => this,
    TheExternalCheckOpened(:final version) => ChecagemExterna(
      version,
      fromTheHome: true,
    ),
    TheExternalCheckLeft() => this,
    TheRecordingLeft() => const Canvas(),
  };
}
