part of '../station.dart';

/// The Checagem externa of one approved Version, reached from the Back-translation or the recording home; a
/// resume point that names it reopens on the Back-translation first (ADR 0116).
final class ChecagemExterna extends Station {
  final int version;

  const ChecagemExterna(this.version);

  @override
  SalaStage get stage => SalaStage.checagem;

  @override
  bool operator ==(Object other) =>
      other is ChecagemExterna && other.version == version;

  @override
  int get hashCode => version.hashCode;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() ||
    TheBackTranslationResumed() ||
    TheExternalCheckLeft() => const Retro(),
    TheExternalCheckOpened() ||
    TheSceneRehearsalOpened() ||
    TheSceneRehearsalLeft() ||
    TheNecklaceClosed() ||
    ThePlanOpened() => this,
  };
}
