part of '../station.dart';

/// The Checagem externa of one approved Version, reached from the Back-translation or the recording home; a
/// resume point that names it reopens on the Back-translation first (ADR 0116).
final class ChecagemExterna extends Station {
  final int version;
  final bool fromTheHome;

  const ChecagemExterna(this.version, {this.fromTheHome = false});

  @override
  SalaStage get stage => SalaStage.checagem;

  @override
  bool operator ==(Object other) =>
      other is ChecagemExterna &&
      other.version == version &&
      other.fromTheHome == fromTheHome;

  @override
  int get hashCode => Object.hash(version, fromTheHome);

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() || TheBackTranslationResumed() => const Retro(),
    TheExternalCheckLeft() => fromTheHome ? const Ensaio() : const Retro(),
    TheExternalCheckOpened() ||
    TheSceneRehearsalOpened() ||
    TheSceneRehearsalLeft() ||
    TheRecordingLeft() ||
    TheNecklaceClosed() ||
    ThePlanOpened() => this,
  };
}
