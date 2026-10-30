import 'channel.dart';
import 'cut_point.dart';
import 'failure_policy.dart';
import 'halt.dart';
import 'left_entry.dart';
import 'scene_rehearsal.dart';
import 'session_snapshot.dart';
import 'station.dart';
import 'turn_result.dart';

sealed class MachineEvent {
  const MachineEvent();
}

/// An event that answers work the machine asked for. [generation] is the generation the
/// answer was stamped with: the one a flow captured, where it checked it just before; the
/// current one everywhere else; and, for the Watch, the one at the moment it fires, so
/// that it survives a generation move. Null is read as the current one.
sealed class AnsweringEvent extends MachineEvent {
  final int? generation;

  const AnsweringEvent({this.generation});
}

final class SessionRead extends AnsweringEvent {
  final SessionSnapshot snapshot;

  const SessionRead(this.snapshot, {super.generation});
}

final class RoomRaisedAHalt extends AnsweringEvent {
  final bool callsForAPerson;

  const RoomRaisedAHalt({this.callsForAPerson = true, super.generation});
}

final class TheAnswerWarned extends AnsweringEvent {
  const TheAnswerWarned({super.generation});
}

final class TeamTapped extends MachineEvent {
  const TeamTapped();
}

final class WatchFired extends AnsweringEvent {
  const WatchFired({super.generation});
}

enum Door {
  outbox,
  watch,
  inbox,
  coverage,
  person,
  resume,
  reply,
  stretches,
  question,
  step,
  telling,
  verdict,
  sceneRehearsal,
  sceneFrase,
  sceneList,
  look,
}

enum PartFact { sent, pending, stranded }

final class NetworkFailedAt extends AnsweringEvent {
  final Door door;

  const NetworkFailedAt(this.door, {super.generation});
}

final class TheRoomAnswered extends AnsweringEvent {
  const TheRoomAnswered({super.generation});
}

typedef TheKeep = ({String session, String kind, String scope, DateTime since});

final class TakeInTheAir {
  final String row;
  final TheKeep keep;

  const TakeInTheAir({required this.row, required this.keep});

  @override
  bool operator ==(Object other) =>
      other is TakeInTheAir && other.row == row && other.keep == keep;

  @override
  int get hashCode => Object.hash(row, keep);
}

final class ATakeLeft extends MachineEvent {
  final TakeInTheAir take;

  const ATakeLeft(this.take);
}

final class ATakeSettled extends MachineEvent {
  final String row;

  const ATakeSettled(this.row);
}

typedef PartOfASession = ({String session, String scope});

final class AKeepBegan extends MachineEvent {
  final PartOfASession part;

  const AKeepBegan(this.part);
}

final class AKeepEnded extends MachineEvent {
  final PartOfASession part;
  final String? row;

  const AKeepEnded(this.part, {this.row});
}

/// The tap «enviar agora» sent [row] up for [part]: from then on it is this visit's.
final class TheTapSent extends MachineEvent {
  final PartOfASession part;
  final String row;

  const TheTapSent(this.part, this.row);
}

final class StopTapped extends MachineEvent {
  final TheKeep keep;

  const StopTapped(this.keep);
}

final class OutboxChanged extends MachineEvent {
  final Map<String, PartFact> parts;

  const OutboxChanged(this.parts);
}

final class LineArrived extends AnsweringEvent {
  final Line line;
  final List<int> by;

  const LineArrived(this.line, {this.by = const [], super.generation});
}

final class PlayerOpened extends AnsweringEvent {
  const PlayerOpened({super.generation});
}

/// [line] or [sound] names what ended; neither is read as whatever is sounding.
final class PlayerEnded extends AnsweringEvent {
  final Line? line;
  final Sound? sound;

  const PlayerEnded({this.line, this.sound, super.generation});
}

final class PlayerFailed extends AnsweringEvent {
  final Source source;
  final Line? line;
  final Sound? sound;

  const PlayerFailed(this.source, {this.line, this.sound, super.generation});
}

final class MicOpened extends AnsweringEvent {
  final MicOwner owner;
  final String take;

  const MicOpened(this.owner, {this.take = '', super.generation});
}

final class MicClosed extends AnsweringEvent {
  const MicClosed({super.generation});
}

/// How the recorder answered the microphone: [started], [refused] or [failed] for an
/// opening; [closed] with the take, or none; [discarded] by the room; [abandoned] when a
/// start that had started came back after the generation moved.
enum MicAnswer { started, refused, failed, closed, discarded, abandoned }

final class MicAnswered extends AnsweringEvent {
  final MicAnswer answer;
  final String? take;
  final Object? because;
  final MicOwner? owner;

  const MicAnswered(
    this.answer, {
    this.take,
    this.because,
    this.owner,
    super.generation,
  });
}

/// A gesture asks for its take: the Microphone stays open until the recorder answers.
final class MicClosing extends MachineEvent {
  const MicClosing();
}

final class MicDiscarded extends MachineEvent {
  const MicDiscarded();
}

final class BeadTapped extends MachineEvent {
  final List<Sound> sounds;
  final Paused? beneath;

  const BeadTapped(this.sounds, {this.beneath});
}

final class PauseTapped extends MachineEvent {
  const PauseTapped();
}

final class TheHeldPartReturns extends MachineEvent {
  final Paused held;

  const TheHeldPartReturns(this.held);
}

final class GestureSilenced extends MachineEvent {
  final bool keepingTheHold;

  const GestureSilenced({this.keepingTheHold = false});
}

final class Interrupted extends MachineEvent {
  final String take;
  final CutPoint cut;

  const Interrupted({required this.take, required this.cut});
}

final class GestureStarted extends MachineEvent {
  final int gesture;

  const GestureStarted(this.gesture);
}

final class GestureEnded extends MachineEvent {
  final int gesture;

  const GestureEnded(this.gesture);
}

final class LineNotSaid extends AnsweringEvent {
  final Line line;
  final Exception? because;

  const LineNotSaid(this.line, {this.because, super.generation});
}

final class StepLeft extends MachineEvent {
  final bool ended;

  const StepLeft({this.ended = false});
}

final class LeftThePassage extends MachineEvent {
  const LeftThePassage();
}

final class TheVerdictAsked extends MachineEvent {
  const TheVerdictAsked();
}

final class TheTranslationStartedOver extends MachineEvent {
  const TheTranslationStartedOver();
}

/// The team arrives at a Station; the Station held answers it after the cross-cutting
/// regions, and it is never stale.
sealed class StationEvent extends MachineEvent {
  const StationEvent();
}

final class TheChoiceOpened extends StationEvent {
  const TheChoiceOpened();
}

final class PassageChosen extends StationEvent {
  const PassageChosen();
}

final class TheRehearsalOpened extends StationEvent {
  const TheRehearsalOpened();
}

/// The orange dot opens the Ensaio Final plan over a passage that has no take yet.
final class ThePlanOpened extends StationEvent {
  const ThePlanOpened();
}

final class TheBackTranslationOpened extends StationEvent {
  const TheBackTranslationOpened();
}

final class TheRoomStartedOver extends StationEvent {
  const TheRoomStartedOver();
}

final class ThePanoramaChosen extends StationEvent {
  final String id;

  const ThePanoramaChosen(this.id);
}

final class TheSceneRehearsalOpened extends StationEvent {
  const TheSceneRehearsalOpened();
}

final class TheSceneRehearsalLeft extends StationEvent {
  const TheSceneRehearsalLeft();
}

final class TheExternalCheckOpened extends StationEvent {
  final int version;

  const TheExternalCheckOpened(this.version);
}

final class TheExternalCheckLeft extends StationEvent {
  const TheExternalCheckLeft();
}

final class TheRecordingLeft extends StationEvent {
  const TheRecordingLeft();
}

/// The team asks for a Panorama in a language: the same one keeps the session the machine
/// holds for it, any other lets that session go.
final class ThePanoramaAsked extends MachineEvent {
  final String id;
  final String language;

  const ThePanoramaAsked(this.id, this.language);
}

/// The room answered a Station's open with its session.
final class TheSessionOpened extends AnsweringEvent {
  final String session;

  const TheSessionOpened(this.session, {super.generation});
}

final class ThePanoramaFound extends AnsweringEvent {
  final String session;
  final bool opened;

  const ThePanoramaFound(
    this.session, {
    required this.opened,
    super.generation,
  });
}

final class TheSessionLetGo extends MachineEvent {
  final String session;

  const TheSessionLetGo(this.session);
}

final class TheWayBackTaken extends MachineEvent {
  final LeftEntry left;

  const TheWayBackTaken(this.left);
}

/// The entry left that waits under the Choice for a failed open to return to.
final class TheEntryWaits extends MachineEvent {
  final LeftEntry left;

  const TheEntryWaits(this.left);
}

/// An open from the Choice ended with no session.
final class TheOpenBroughtNoSession extends MachineEvent {
  const TheOpenBroughtNoSession();
}

final class TheLeftPassageReturns extends MachineEvent {
  final String session;
  final bool warned;

  const TheLeftPassageReturns(this.session, {this.warned = false});
}

final class TheLanguageChosen extends MachineEvent {
  const TheLanguageChosen();
}

/// The Rehearsal's parts or its scene list changed: whether every scene has its part, and
/// whether every part is sent.
final class TheRehearsalWeighed extends MachineEvent {
  final bool everySceneHasItsPart;
  final bool everyPartIsSent;

  const TheRehearsalWeighed({
    required this.everySceneHasItsPart,
    required this.everyPartIsSent,
  });
}

final class TheSessionIsGone extends AnsweringEvent {
  const TheSessionIsGone({super.generation});
}

final class ThePassageClosed extends AnsweringEvent {
  const ThePassageClosed({super.generation});
}

/// One turn: the session it was spoken into and the id it keeps.
final class Turn {
  final String sessionId;
  final String turnId;

  const Turn(this.sessionId, this.turnId);

  @override
  bool operator ==(Object other) =>
      other is Turn && other.sessionId == sessionId && other.turnId == turnId;

  @override
  int get hashCode => Object.hash(sessionId, turnId);
}

final class TurnSent extends MachineEvent {
  final Turn turn;
  final Kept keeps;

  const TurnSent(this.turn, {this.keeps = const NothingKept()});
}

final class TurnAnswered extends AnsweringEvent {
  final Turn turn;

  const TurnAnswered(this.turn, {super.generation});
}

/// The turn came back refused or with its session gone: it is no longer in flight, and
/// what it was owed stays owed.
final class TurnFailed extends AnsweringEvent {
  final Turn turn;

  const TurnFailed(this.turn, {super.generation});
}

final class TurnGivenUp extends AnsweringEvent {
  final Turn turn;
  final Kept sounding;

  const TurnGivenUp(
    this.turn, {
    this.sounding = const NothingKept(),
    super.generation,
  });
}

final class LookFound extends AnsweringEvent {
  final Turn turn;
  final TurnResult reply;

  const LookFound(this.turn, this.reply, {super.generation});
}

final class LookEmpty extends AnsweringEvent {
  final Turn turn;
  final Kept sounding;

  /// The busy watchdog ran out over a look the room was still answering.
  final bool theWaitRanOut;

  const LookEmpty(
    this.turn, {
    this.sounding = const NothingKept(),
    this.theWaitRanOut = false,
    super.generation,
  });
}

/// The [load]th load of one reply failed; [answered] hears whether the reply is loaded
/// again.
///
/// It carries no generation: it is never stale only because the notifier dispatches it
/// synchronously, right after checking that the generation was not abandoned (ADR 0152).
final class TheReplyFailedToLoad extends MachineEvent {
  final int load;
  final RoomResult? because;
  final Kept sounding;
  final void Function(bool loadAgain) answered;

  const TheReplyFailedToLoad(
    this.load, {
    required this.answered,
    this.because,
    this.sounding = const NothingKept(),
  });

  TheSoundFailed get failure => TheSoundFailed(load, because: because);
}

final class LookFailed extends AnsweringEvent {
  final Turn turn;
  final RoomResult result;
  final Kept sounding;

  const LookFailed(
    this.turn,
    this.result, {
    this.sounding = const NothingKept(),
    super.generation,
  });
}

/// The room is still answering the turn the look asked for.
final class LookPending extends AnsweringEvent {
  final Turn turn;
  final Kept sounding;

  const LookPending(
    this.turn, {
    this.sounding = const NothingKept(),
    super.generation,
  });
}

final class TheOpeningMissed extends AnsweringEvent {
  const TheOpeningMissed({super.generation});
}

final class ThePassageCannotOpen extends AnsweringEvent {
  const ThePassageCannotOpen({super.generation});
}

final class TheRefusalPassed extends AnsweringEvent {
  const TheRefusalPassed({super.generation});
}

final class TheHandFailed extends AnsweringEvent {
  const TheHandFailed({super.generation});
}

/// The passage's scenes could not be had: the take goes unlabelled, nothing else moves.
final class TheScenesMissed extends AnsweringEvent {
  const TheScenesMissed({super.generation});
}

/// The scene rehearsals the room listed when they were read again.
final class TheSceneRehearsalsListed extends AnsweringEvent {
  final List<SceneRehearsalRecord> listed;

  const TheSceneRehearsalsListed(this.listed, {super.generation});
}

/// A scene door failed; [readAgain] when the room's refusal says the rehearsal moved on
/// without this tablet, sent to the voice or restarted by an answer it never heard, or
/// when it refused «terminei» with a code that stops the room.
final class TheSceneDoorFailed extends AnsweringEvent {
  final bool readAgain;

  const TheSceneDoorFailed({this.readAgain = false, super.generation});
}

/// The room refused «terminei» because the rehearsal had already gone to the voice.
final class TheSceneWentAlready extends AnsweringEvent {
  const TheSceneWentAlready({super.generation});
}

/// The room refused «terminei» for a reason a later tap can mend.
final class TheSceneSendRefused extends AnsweringEvent {
  const TheSceneSendRefused({super.generation});
}

/// The tablet's disk could not keep audio a scene door brought in.
final class TheSceneDiskFailed extends AnsweringEvent {
  const TheSceneDiskFailed({super.generation});
}

final class TheCallWasRefused extends AnsweringEvent {
  const TheCallWasRefused({super.generation});
}

final class TheCallMetAClosedPassage extends AnsweringEvent {
  const TheCallMetAClosedPassage({super.generation});
}

final class TheTellingCameBackEmpty extends AnsweringEvent {
  final bool readAgain;

  const TheTellingCameBackEmpty({this.readAgain = false, super.generation});
}

final class TheStepFailed extends AnsweringEvent {
  const TheStepFailed({super.generation});
}

final class TheResumeFailed extends AnsweringEvent {
  const TheResumeFailed({super.generation});
}

final class TheSceneTurnFoundNothing extends AnsweringEvent {
  const TheSceneTurnFoundNothing({super.generation});
}

sealed class Effect {
  const Effect();
}

/// An effect whose work is the Station's own lifecycle, handed over to it through one
/// narrow callback (ENG-1444).
sealed class LifecycleHandOff extends Effect {
  const LifecycleHandOff();
}

final class SilenceTheRoom extends LifecycleHandOff {
  const SilenceTheRoom();
}

final class CloseAndDiscardTheMic extends Effect {
  const CloseAndDiscardTheMic();
}

final class CloseTheMic extends Effect {
  final MicOwner? owner;

  const CloseTheMic({this.owner});
}

final class DiscardTheMic extends Effect {
  const DiscardTheMic();
}

final class ArmTheWatch extends Effect {
  const ArmTheWatch();
}

final class CallForAPerson extends Effect {
  const CallForAPerson();
}

final class StopCallingForAPerson extends Effect {
  const StopCallingForAPerson();
}

final class ReadTheState extends Effect {
  const ReadTheState();
}

final class GoOnAfterTheSign extends Effect {
  const GoOnAfterTheSign();
}

final class LetTheOpeningGo extends Effect {
  const LetTheOpeningGo();
}

final class PlayLine extends Effect {
  final Line line;

  const PlayLine(this.line);

  @override
  bool operator ==(Object other) => other is PlayLine && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

final class PlayPart extends Effect {
  final PartSound part;

  const PlayPart(this.part);

  @override
  bool operator ==(Object other) => other is PlayPart && other.part == part;

  @override
  int get hashCode => part.hashCode;
}

final class PlayStretch extends Effect {
  final StretchSound stretch;

  const PlayStretch(this.stretch);

  @override
  bool operator ==(Object other) =>
      other is PlayStretch && other.stretch == stretch;

  @override
  int get hashCode => stretch.hashCode;
}

final class OpenTheMic extends Effect {
  final MicOwner owner;
  final String take;

  const OpenTheMic(this.owner, {this.take = ''});

  @override
  bool operator ==(Object other) =>
      other is OpenTheMic && other.owner == owner && other.take == take;

  @override
  int get hashCode => Object.hash(owner, take);
}

/// Stops the voice; [line] names the line it cuts, when one is speaking.
final class StopTheLine extends Effect {
  final Line? line;

  const StopTheLine([this.line]);

  @override
  bool operator ==(Object other) => other is StopTheLine && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

final class DropTheLine extends Effect {
  final Line line;

  const DropTheLine(this.line);

  @override
  bool operator ==(Object other) => other is DropTheLine && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

/// The part's ceiling, once the machine has taken the part's opening.
final class ArmTheCeiling extends Effect {
  const ArmTheCeiling();
}

final class StopTheSound extends Effect {
  const StopTheSound();
}

final class HoldTheSound extends Effect {
  const HoldTheSound();
}

final class LetTheSoundRun extends Effect {
  const LetTheSoundRun();
}

final class StopTheSend extends Effect {
  final String row;

  const StopTheSend(this.row);

  @override
  bool operator ==(Object other) => other is StopTheSend && other.row == row;

  @override
  int get hashCode => row.hashCode;
}

final class DiscardTheSession extends LifecycleHandOff {
  const DiscardTheSession();
}

final class OpenTheChoice extends LifecycleHandOff {
  const OpenTheChoice();
}

final class ReadTheWheel extends LifecycleHandOff {
  const ReadTheWheel();
}

final class OpenThePanorama extends LifecycleHandOff {
  final String id;
  final String? language;

  const OpenThePanorama(this.id, this.language);

  @override
  bool operator ==(Object other) =>
      other is OpenThePanorama && other.id == id && other.language == language;

  @override
  int get hashCode => Object.hash(id, language);
}

/// The Panorama comes back in silence: its line was said on the session it still holds.
final class ReturnToThePanorama extends LifecycleHandOff {
  const ReturnToThePanorama();
}

final class RestOnThePanorama extends LifecycleHandOff {
  const RestOnThePanorama();
}

final class EnterThePassageLeft extends LifecycleHandOff {
  final LeftEntry left;

  const EnterThePassageLeft(this.left);

  @override
  bool operator ==(Object other) =>
      other is EnterThePassageLeft && other.left == left;

  @override
  int get hashCode => left.hashCode;
}

final class ReturnToTheEntryLeft extends LifecycleHandOff {
  final LeftEntry left;

  const ReturnToTheEntryLeft(this.left);

  @override
  bool operator ==(Object other) =>
      other is ReturnToTheEntryLeft && other.left == left;

  @override
  int get hashCode => left.hashCode;
}

final class RestOnTheChoice extends LifecycleHandOff {
  const RestOnTheChoice();
}

final class LookAtTheSession extends Effect {
  final Turn turn;
  final Kept sounding;

  const LookAtTheSession(this.turn, {this.sounding = const NothingKept()});

  @override
  bool operator ==(Object other) =>
      other is LookAtTheSession &&
      other.turn == turn &&
      other.sounding == sounding;

  @override
  int get hashCode => Object.hash(turn, sounding);
}

final class PlayTheReply extends Effect {
  final Turn turn;
  final TurnResult reply;

  const PlayTheReply(this.turn, this.reply);
}

/// The look found a reply the team rests on without hearing it: «Ouvir de novo» says it.
final class KeepTheReply extends Effect {
  final Turn turn;
  final TurnResult reply;

  const KeepTheReply(this.turn, this.reply);
}

final class LookAgain extends Effect {
  final Turn turn;
  final Kept sounding;

  const LookAgain(this.turn, {this.sounding = const NothingKept()});

  @override
  bool operator ==(Object other) =>
      other is LookAgain && other.turn == turn && other.sounding == sounding;

  @override
  int get hashCode => Object.hash(turn, sounding);
}

final class LetTheLineGo extends Effect {
  const LetTheLineGo();
}

final class LoadTheReplyAgain extends Effect {
  final void Function(bool loadAgain) answered;

  const LoadTheReplyAgain(this.answered);

  @override
  bool operator ==(Object other) =>
      other is LoadTheReplyAgain && other.answered == answered;

  @override
  int get hashCode => answered.hashCode;
}

final class LetTheReplyGo extends Effect {
  final void Function(bool loadAgain) answered;
  final MachineEvent decided;

  const LetTheReplyGo(this.answered, {required this.decided});

  @override
  bool operator ==(Object other) =>
      other is LetTheReplyGo &&
      other.answered == answered &&
      other.decided == decided;

  @override
  int get hashCode => Object.hash(answered, decided);
}

final class StopLooking extends Effect {
  const StopLooking();
}

/// The look a halt suspended goes on after its lift, under the busy watchdog.
final class ResumeTheWait extends Effect {
  const ResumeTheWait();
}

final class LetTheTurnGo extends Effect {
  final Turn turn;

  const LetTheTurnGo(this.turn);

  @override
  bool operator ==(Object other) => other is LetTheTurnGo && other.turn == turn;

  @override
  int get hashCode => turn.hashCode;
}

final class AskForAPersonAgain extends Effect {
  const AskForAPersonAgain();
}

final class CloseThePassage extends Effect {
  const CloseThePassage();
}

final class LetTheStepGo extends Effect {
  const LetTheStepGo();
}

final class LetThePendingTranslationGo extends Effect {
  const LetThePendingTranslationGo();
}

final class RefuseThePassage extends Effect {
  const RefuseThePassage();
}

final class ReadTheSceneRehearsals extends Effect {
  const ReadTheSceneRehearsals();
}

final class AskTheFraseAgain extends Effect {
  const AskTheFraseAgain();
}

final class TellTheDiskFailed extends Effect {
  const TellTheDiskFailed();
}

final class TellThePlayFailed extends Effect {
  const TellThePlayFailed();
}

final class TellThePlayOpened extends Effect {
  const TellThePlayOpened();
}

final class TellTheSendFailed extends Effect {
  const TellTheSendFailed();
}

final class TellItWentAlready extends Effect {
  const TellItWentAlready();
}

/// The room may have kept the frase whose answer was lost: its list decides.
final class AskTheFraseAgainAfterTheList extends Effect {
  const AskTheFraseAgainAfterTheList();
}

final class ShowTheSceneRehearsals extends Effect {
  final List<SceneRehearsalRecord> listed;

  const ShowTheSceneRehearsals(this.listed);
}

/// How a line ended: said whole, failed, not said, or cut by the team, which counts as
/// heard.
enum Said {
  said,
  failed,
  unsaid,
  cut;

  bool get heard => this == said || this == cut;
}

/// How the last line the room answered for ended, for the gesture that waits on it.
final class LineOutcome {
  final Line line;
  final Said said;
  final Exception? because;

  const LineOutcome(this.line, this.said, {this.because});
}

/// How the microphone last answered, for the Station and the gesture waiting on its take.
final class MicOutcome {
  final MicAnswer answer;
  final String? take;
  final Object? because;
  final CutPoint? cut;
  final MicOwner? owner;

  const MicOutcome(
    this.answer, {
    this.take,
    this.because,
    this.cut,
    this.owner,
  });
}

/// The Panorama the room holds across the Choice: its id, the language it was asked in,
/// and its session once the room opened one.
final class HeldPanorama {
  final String id;
  final String language;
  final String? session;

  const HeldPanorama(this.id, this.language, {this.session});

  @override
  bool operator ==(Object other) =>
      other is HeldPanorama &&
      other.id == id &&
      other.language == language &&
      other.session == session;

  @override
  int get hashCode => Object.hash(id, language, session);
}

/// The one look at a turn the tablet gave up on.
final class TheLook {
  final Turn turn;
  final Kept sounding;

  /// The room said it is still answering the turn.
  final bool stillAnswering;

  /// The look went out: false for a turn given up under a halt.
  final bool asked;

  /// A halt holds the look back.
  final bool suspended;

  const TheLook(
    this.turn, {
    this.sounding = const NothingKept(),
    this.stillAnswering = false,
    this.asked = true,
    this.suspended = false,
  });

  TheLook copyWith({bool? stillAnswering, bool? asked, bool? suspended}) =>
      TheLook(
        turn,
        sounding: sounding,
        stillAnswering: stillAnswering ?? this.stillAnswering,
        asked: asked ?? this.asked,
        suspended: suspended ?? this.suspended,
      );

  @override
  bool operator ==(Object other) =>
      other is TheLook &&
      other.turn == turn &&
      other.sounding == sounding &&
      other.stillAnswering == stillAnswering &&
      other.asked == asked &&
      other.suspended == suspended;

  @override
  int get hashCode =>
      Object.hash(turn, sounding, stillAnswering, asked, suspended);
}

final class Machine {
  final Halt halt;
  final Channel channel;
  final List<Line> queue;
  final Set<int> onTheirWay;
  final Map<Line, Set<int>> owners;
  final Map<String, PartFact> parts;
  final TakeInTheAir? inTheAir;
  final Map<PartOfASession, int> keeping;
  final Map<String, PartOfASession> keptThisVisit;
  final int generation;

  /// The turn whose POST is in the air: sent, and neither answered nor given up.
  final Turn? inFlight;

  /// What the turn in flight keeps to sound if it is given up.
  final Kept keptInFlight;

  /// The turn the one look reads, from its give-up until the look is decided. A halt
  /// suspends it and the team's tap resumes it.
  final TheLook? look;

  bool get holdsATurn => inFlight != null || look != null;

  final LineOutcome? lastLine;

  final MicOutcome? lastMic;

  final Station station;

  final bool wordlessTelling;

  /// A halt met on the scene rehearsal, the external check or the
  /// back-translation: the person sign shows once the team is back on the Canvas.
  final RoomRaisedAHalt? aHaltWaitsForTheCanvas;

  final bool theCanvasEnded;

  /// The passage's session.
  final String? session;

  final HeldPanorama? panorama;

  /// The passage or said Panorama left under the Choice, which a failed open returns to.
  final LeftEntry? waiting;

  const Machine({
    this.halt = const NoHalt(),
    this.channel = const Silence(),
    this.queue = const [],
    this.onTheirWay = const {},
    this.owners = const {},
    this.parts = const {},
    this.inTheAir,
    this.keeping = const {},
    this.keptThisVisit = const {},
    this.generation = 0,
    this.inFlight,
    this.keptInFlight = const NothingKept(),
    this.look,
    this.lastLine,
    this.lastMic,
    this.station = const Menu(),
    this.wordlessTelling = false,
    this.aHaltWaitsForTheCanvas,
    this.theCanvasEnded = false,
    this.session,
    this.panorama,
    this.waiting,
  });

  String? get stationSession =>
      station is Panorama ? panorama?.session : session;

  Machine withTheOutboxOf(Machine before) => copyWith(
    parts: before.parts,
    inTheAir: before.inTheAir,
    keeping: before.keeping,
    keptThisVisit: before.keptThisVisit,
  );

  bool beingKept(String? session, String scope) =>
      session != null && (keeping[(session: session, scope: scope)] ?? 0) > 0;

  PartFact? newestKeptFact(String? session, String scope) {
    String? newest;
    for (final MapEntry(key: row, value: kept) in keptThisVisit.entries) {
      if (kept.session == session && kept.scope == scope) newest = row;
    }
    return newest == null ? null : parts[newest];
  }

  Set<String> savedParts(String? session) {
    final newest = <String, String>{};
    for (final MapEntry(key: row, value: kept) in keptThisVisit.entries) {
      if (kept.session == session) newest[kept.scope] = row;
    }
    return {
      for (final MapEntry(key: scope, value: row) in newest.entries)
        if (!beingKept(session, scope) && parts[row] == PartFact.sent) scope,
    };
  }

  Machine withNoPassage(Set<int> onTheirWay) => Machine(
    onTheirWay: onTheirWay,
    generation: generation,
    station: station,
    panorama: panorama,
  ).withTheOutboxOf(this);

  Machine copyWith({
    Halt? halt,
    Channel? channel,
    List<Line>? queue,
    Set<int>? onTheirWay,
    Map<Line, Set<int>>? owners,
    Map<String, PartFact>? parts,
    TakeInTheAir? inTheAir,
    bool landTheTake = false,
    Map<PartOfASession, int>? keeping,
    Map<String, PartOfASession>? keptThisVisit,
    int? generation,
    Turn? inFlight,
    bool landTheTurn = false,
    Kept? keptInFlight,
    TheLook? look,
    bool forgetTheLook = false,
    LineOutcome? lastLine,
    MicOutcome? lastMic,
    Station? station,
    bool? wordlessTelling,
    RoomRaisedAHalt? aHaltWaitsForTheCanvas,
    bool letTheWaitingHaltGo = false,
    bool? theCanvasEnded,
    String? session,
    bool clearSession = false,
    HeldPanorama? panorama,
    bool clearPanorama = false,
    LeftEntry? waiting,
    bool clearWaiting = false,
  }) => Machine(
    halt: halt ?? this.halt,
    channel: channel ?? this.channel,
    queue: queue ?? this.queue,
    onTheirWay: onTheirWay ?? this.onTheirWay,
    owners: owners ?? this.owners,
    parts: parts ?? this.parts,
    inTheAir: landTheTake ? null : (inTheAir ?? this.inTheAir),
    keeping: keeping ?? this.keeping,
    keptThisVisit: keptThisVisit ?? this.keptThisVisit,
    generation: generation ?? this.generation,
    inFlight: landTheTurn ? null : (inFlight ?? this.inFlight),
    keptInFlight: landTheTurn
        ? const NothingKept()
        : (keptInFlight ?? this.keptInFlight),
    look: forgetTheLook ? null : (look ?? this.look),
    lastLine: lastLine ?? this.lastLine,
    lastMic: lastMic ?? this.lastMic,
    station: station ?? this.station,
    wordlessTelling: wordlessTelling ?? this.wordlessTelling,
    aHaltWaitsForTheCanvas: letTheWaitingHaltGo
        ? null
        : (aHaltWaitsForTheCanvas ?? this.aHaltWaitsForTheCanvas),
    theCanvasEnded: theCanvasEnded ?? this.theCanvasEnded,
    session: clearSession ? null : (session ?? this.session),
    panorama: clearPanorama ? null : (panorama ?? this.panorama),
    waiting: clearWaiting ? null : (waiting ?? this.waiting),
  );
}

Machine moveTheGeneration(Machine machine) => machine.copyWith(
  generation: machine.generation + 1,
  landTheTurn: true,
  forgetTheLook: true,
);

const _enter = [SilenceTheRoom(), CloseAndDiscardTheMic()];
const _watch = ArmTheWatch();

(Machine, List<Effect>) reduce(
  Machine machine,
  MachineEvent event,
) => switch (event) {
  AnsweringEvent(:final generation?) when generation < machine.generation => (
    machine,
    const [],
  ),
  LineArrived(:final line, :final by) => _arrive(machine, line, by),
  PlayerOpened() => (
    _opened(machine),
    [
      if (machine.channel is Playing) const ArmTheCeiling(),
      if (machine.channel case Playing(
        sound: PartSound() || StretchSound(telling: false),
      ) when machine.station is Retro)
        const TellThePlayOpened(),
    ],
  ),
  PlayerEnded(:final line?) => _answer(
    machine,
    line,
    Said.said,
    heard: () => _ended(
      machine.station is Retro && line.url != null
          ? machine.copyWith(letTheWaitingHaltGo: true)
          : machine,
    ),
  ),
  PlayerFailed(:final line?) => _answer(
    machine,
    line,
    Said.failed,
    heard: () => _failed(machine),
  ),
  PlayerEnded(:final sound?) when !_sounds(machine, sound, orHeld: true) => (
    machine,
    const [],
  ),
  PlayerFailed(:final sound?) when !_sounds(machine, sound) => (
    machine,
    const [],
  ),
  PlayerEnded() => _ended(machine),
  PlayerFailed(sound: PartSound() || StretchSound(telling: false))
      when machine.station is Retro =>
    _tellThePlayFailed(machine),
  PlayerFailed() => _failed(machine),
  MicOpened(:final owner, :final take) => _openTheMic(machine, owner, take),
  MicClosed() => _closeTheMic(machine),
  MicAnswered(:final answer, :final take, :final because, :final owner) =>
    _heard(machine, answer, take, because, owner),
  MicClosing() => (
    machine,
    [
      CloseTheMic(
        owner: switch (machine.channel) {
          Microphone(:final owner) => owner,
          _ => null,
        },
      ),
    ],
  ),
  MicDiscarded() => _discardTheMic(machine),
  BeadTapped(:final sounds, :final beneath) => _tapped(
    machine,
    sounds,
    beneath,
  ),
  PauseTapped() => _pause(machine),
  TheHeldPartReturns(:final held) => (
    machine.channel is Silence && machine.halt is! Blocking
        ? machine.copyWith(channel: held)
        : machine,
    const [],
  ),
  GestureSilenced(:final keepingTheHold) => (
    _silenced(machine, keepingTheHold),
    keepingTheHold
        ? [StopTheLine(_speaking(machine.channel))]
        : const [StopTheSound()],
  ),
  Interrupted(:final take, :final cut) => _interrupt(machine, take, cut),
  GestureStarted(:final gesture) => (
    machine.copyWith(onTheirWay: {...machine.onTheirWay, gesture}),
    const [],
  ),
  GestureEnded(:final gesture) => _drain(
    machine.copyWith(onTheirWay: {...machine.onTheirWay}..remove(gesture)),
  ),
  LineNotSaid(:final line, :final because) => _answer(
    machine,
    line,
    because == null ? Said.unsaid : Said.failed,
    because: because,
    heard: () => _notSaid(machine, line),
    unheard: () => _notSaid(machine, line),
  ),
  StepLeft(:final ended) => _leaveTheQueue(
    machine.station is Canvas
        ? machine.copyWith(theCanvasEnded: ended)
        : machine,
    (_) => true,
  ),
  LeftThePassage() => (
    machine.copyWith(
      channel: const Silence(),
      queue: const [],
      owners: const {},
    ),
    [const StopTheSound(), for (final line in machine.queue) DropTheLine(line)],
  ),
  TheSessionIsGone() || ThePassageClosed() => _theSessionGone(machine),
  TheCallMetAClosedPassage() => (machine, const [CloseThePassage()]),
  TurnSent(:final turn, :final keeps) => (
    machine.copyWith(inFlight: turn, keptInFlight: keeps),
    const [],
  ),
  TurnAnswered(:final turn) => (
    _land(machine, turn).copyWith(letTheWaitingHaltGo: true),
    const [],
  ),
  TurnFailed(:final turn) => (_land(machine, turn), const []),
  TurnGivenUp(:final turn, :final sounding) => _giveUp(machine, turn, sounding),
  LookFound(:final turn) ||
  LookPending(:final turn) ||
  LookEmpty(:final turn) ||
  LookFailed(
    :final turn,
  ) when machine.look?.turn != turn => (machine, const []),
  LookFound(:final turn, :final reply) => (
    machine.copyWith(forgetTheLook: true, letTheWaitingHaltGo: true),
    [
      if (machine.look case TheLook(
        sounding: TheOpening(),
        stillAnswering: true,
      ))
        KeepTheReply(turn, reply)
      else
        PlayTheReply(turn, reply),
    ],
  ),
  TheRefusalPassed() => _resumeTheLook(machine),
  TheHandFailed() => (machine, const []),
  TheScenesMissed() => (machine, const []),
  TheSceneWentAlready() when machine.station is SceneRehearsal => (
    machine.copyWith(letTheWaitingHaltGo: true),
    const [TellItWentAlready(), ReadTheSceneRehearsals()],
  ),
  TheSceneSendRefused() when machine.station is SceneRehearsal => (
    machine.copyWith(letTheWaitingHaltGo: true),
    const [TellTheSendFailed(), ReadTheSceneRehearsals()],
  ),
  TheSceneWentAlready() || TheSceneSendRefused() => (machine, const []),
  TheSceneDoorFailed(readAgain: true) when machine.station is SceneRehearsal =>
    (machine, const [ReadTheSceneRehearsals()]),
  TheSceneDoorFailed() => (machine, const []),
  TheSceneDiskFailed()
      when switch (machine.station) {
        SceneRehearsal() || Ensaio(step: EnsaioStep.plan) => true,
        _ => false,
      } =>
    (machine, const [TellTheDiskFailed()]),
  TheSceneDiskFailed() => (machine, const []),
  TheSceneRehearsalsListed(:final listed)
      when machine.station is SceneRehearsal =>
    (machine, [ShowTheSceneRehearsals(listed)]),
  TheSceneRehearsalsListed() => (machine, const []),
  TheCallWasRefused() => (machine, const [AskForAPersonAgain()]),
  LookPending(:final turn) => (
    machine.copyWith(
      look: machine.look!.copyWith(stillAnswering: true, asked: true),
    ),
    [
      if (machine.halt is! Blocking)
        LookAgain(turn, sounding: machine.look!.sounding),
    ],
  ),
  LookEmpty(:final turn, theWaitRanOut: false) ||
  LookFailed(:final turn) when machine.look?.stillAnswering ?? false => (
    machine,
    [
      if (machine.halt is! Blocking)
        LookAgain(turn, sounding: machine.look!.sounding),
    ],
  ),
  LookEmpty(sounding: final sounding && (TheOpening() || TheLineSaidAgain())) ||
  LookFailed(
    sounding: final sounding && (TheOpening() || TheLineSaidAgain()),
  ) => (
    machine.copyWith(forgetTheLook: true),
    [
      if (sounding is TheLineSaidAgain)
        const LetTheLineGo()
      else
        const LetTheOpeningGo(),
      if (event case LookEmpty(theWaitRanOut: true)) const StopLooking(),
    ],
  ),
  LookFailed(:final turn, :final result, :final sounding) => reduce(
    machine.copyWith(forgetTheLook: true),
    FailurePolicy.decide(
      result,
      FailureContext(
        station: machine.station,
        generation: machine.generation,
        turn: turn,
        sounding: sounding,
        door: Door.look,
      ),
    ),
  ),
  TheOpeningMissed() => (machine, const [LetTheOpeningGo()]),
  TheReplyFailedToLoad() => _theReplyFailed(machine, event),
  LookEmpty(:final turn, :final sounding, :final theWaitRanOut) =>
    switch (reduce(
      machine.copyWith(forgetTheLook: true),
      FailurePolicy.decide(
        const RoomFoundNothing(),
        FailureContext(
          station: machine.station,
          generation: machine.generation,
          turn: turn,
          sounding: sounding,
        ),
      ),
    )) {
      (final decided, final effects) => (
        decided,
        [...effects, if (theWaitRanOut) const StopLooking()],
      ),
    },
  ThePassageCannotOpen() => _orBackToWhatWaits(
    machine,
    const [],
    const RefuseThePassage(),
  ),
  TheStepFailed() => (machine, const [LetTheStepGo()]),
  TheResumeFailed() => _theResumeFailed(machine),
  TheOpenBroughtNoSession() => _orBackToWhatWaits(
    machine,
    const [],
    const RestOnTheChoice(),
  ),
  TheSceneTurnFoundNothing() when machine.station is SceneRehearsal => (
    machine.copyWith(aHaltWaitsForTheCanvas: const RoomRaisedAHalt()),
    const [LetTheStepGo(), TellTheSendFailed(), ReadTheSceneRehearsals()],
  ),
  TheSceneTurnFoundNothing() => reduce(machine, const RoomRaisedAHalt()),
  TheTellingCameBackEmpty() when machine.station is Retro => (
    machine.copyWith(wordlessTelling: true),
    const [LetThePendingTranslationGo()],
  ),
  TheTellingCameBackEmpty(readAgain: true)
      when machine.station is SceneRehearsal =>
    (machine, const [AskTheFraseAgainAfterTheList()]),
  TheTellingCameBackEmpty() when machine.station is SceneRehearsal => (
    machine,
    const [AskTheFraseAgain()],
  ),
  TheTellingCameBackEmpty() => (machine, const []),
  TheVerdictAsked() => (machine.copyWith(wordlessTelling: false), const []),
  TheTranslationStartedOver() => (
    machine.copyWith(wordlessTelling: false),
    const [],
  ),
  NetworkFailedAt(:final door) => (
    machine,
    [if (door == Door.step || door == Door.verdict) const LetTheStepGo()],
  ),
  TheRoomAnswered() => (machine, const []),
  OutboxChanged(:final parts) => (machine.copyWith(parts: parts), const []),
  ATakeLeft(:final take) => (machine.copyWith(inTheAir: take), const []),
  AKeepBegan(:final part) => (
    machine.copyWith(
      keeping: {...machine.keeping, part: (machine.keeping[part] ?? 0) + 1},
    ),
    const [],
  ),
  AKeepEnded(:final part, :final row) => (
    machine.copyWith(
      keeping: {
        for (final MapEntry(key: kept, value: keeps) in machine.keeping.entries)
          if (kept != part || keeps > 1) kept: kept == part ? keeps - 1 : keeps,
      },
      keptThisVisit: {...machine.keptThisVisit, ?row: part},
    ),
    const [],
  ),
  TheTapSent(:final part, :final row) => (
    machine.copyWith(keptThisVisit: {...machine.keptThisVisit, row: part}),
    const [],
  ),
  ATakeSettled(:final row) => (
    machine.copyWith(landTheTake: machine.inTheAir?.row == row),
    const [],
  ),
  StopTapped(:final keep) => (
    machine,
    [
      if (machine.inTheAir case final take?
          when take.keep == keep && keep.session == machine.session)
        StopTheSend(take.row),
    ],
  ),
  SessionRead() => switch (_theHalt(machine, event)) {
    (final read, final effects) => switch (_resumeTheLook(read)) {
      (final resumed, final looks) => (resumed, [...effects, ...looks]),
    },
  },
  RoomRaisedAHalt(:final callsForAPerson)
      when machine.station is SceneRehearsal ||
          machine.station is ChecagemExterna ||
          machine.station is Retro =>
    (
      machine.copyWith(
        aHaltWaitsForTheCanvas: RoomRaisedAHalt(
          callsForAPerson:
              callsForAPerson ||
              (machine.aHaltWaitsForTheCanvas?.callsForAPerson ?? false),
        ),
      ),
      const <Effect>[],
    ),
  RoomRaisedAHalt() ||
  TheAnswerWarned() ||
  TeamTapped() ||
  WatchFired() => _theHalt(machine, event),
  TheLanguageChosen() => switch (machine.station) {
    Menu() => (moveTheGeneration(machine), const [ReadTheWheel()]),
    _ => (machine, const []),
  },
  ThePanoramaAsked(:final id, :final language) => switch (machine.panorama) {
    HeldPanorama(id: final held, language: final spoken)
        when held == id && spoken == language =>
      (machine, const []),
    _ => (machine.copyWith(panorama: HeldPanorama(id, language)), const []),
  },
  TheSessionOpened(:final session) => (
    switch (machine.panorama) {
      final HeldPanorama held when machine.station is Panorama =>
        machine.copyWith(
          panorama: HeldPanorama(held.id, held.language, session: session),
        ),
      _ when machine.station is Panorama => machine,
      _ => machine.copyWith(session: session),
    }.copyWith(clearWaiting: true),
    const [_watch],
  ),
  ThePanoramaFound(:final session, :final opened) => switch (machine.panorama) {
    final HeldPanorama held when machine.station is Panorama => (
      machine.copyWith(
        panorama: HeldPanorama(held.id, held.language, session: session),
        clearWaiting: true,
      ),
      [
        _watch,
        if (opened) const RestOnThePanorama(),
        if (!opened) OpenThePanorama(held.id, held.language),
      ],
    ),
    _ => (machine, const []),
  },
  TheSessionLetGo(:final session) when machine.waiting?.session == session =>
    reduce(machine.copyWith(clearWaiting: true), event),
  TheSessionLetGo(:final session) => switch (machine.panorama) {
    final HeldPanorama held when held.session == session => (
      machine.copyWith(panorama: HeldPanorama(held.id, held.language)),
      const [],
    ),
    _ => (machine, const []),
  },
  TheEntryWaits(:final left) => (
    switch (left) {
      LeftEntry(panorama: false, session: _?) => machine.copyWith(
        waiting: left,
      ),
      LeftEntry(
        panorama: true,
        said: true,
        pericope: _?,
        language: _?,
        :final session?,
      )
          when machine.panorama?.session == session =>
        machine.copyWith(waiting: left),
      _ => machine.copyWith(clearWaiting: true),
    },
    const [],
  ),
  TheRehearsalWeighed(:final everySceneHasItsPart, :final everyPartIsSent) =>
    switch (machine.station) {
      Ensaio(:final step) => (
        machine.copyWith(
          station: Ensaio(
            everySceneHasItsPart: everySceneHasItsPart,
            everyPartIsSent: everyPartIsSent,
            step: step,
          ),
        ),
        const [],
      ),
      _ => (machine, const []),
    },
  TheWayBackTaken(:final left) => _takeTheWayBack(
    machine.copyWith(clearWaiting: true),
    left,
  ),
  TheLeftPassageReturns(:final session, :final warned) => (
    machine.copyWith(
      clearWaiting: true,
      session: session,
      halt: warned ? const Warning() : const NoHalt(),
    ),
    const [_watch],
  ),
  StationEvent() => _reachTheStation(machine, event),
};

/// A failed open returns to what waits under the Choice, its Panorama held again.
(Machine, List<Effect>) _orBackToWhatWaits(
  Machine machine,
  List<Effect> leaving,
  Effect toTheChoice,
) => switch (machine.waiting) {
  final LeftEntry left => (
    machine.copyWith(
      clearWaiting: true,
      panorama: left.panorama
          ? HeldPanorama(left.pericope!, left.language!, session: left.session)
          : null,
    ),
    [...leaving, ReturnToTheEntryLeft(left)],
  ),
  null => (machine, [...leaving, toTheChoice]),
};

/// The Panorama comes back silent once its line was said on the session the machine
/// still holds; any other entry left is entered again in the language it was left in.
(Machine, List<Effect>) _takeTheWayBack(Machine machine, LeftEntry left) {
  switch (left) {
    case LeftEntry(panorama: true, pericope: final id?):
      final (arrived, effects) = _reachTheStation(
        machine,
        ThePanoramaChosen(id),
      );
      final held = machine.panorama;
      final silent =
          left.said &&
          held != null &&
          held.id == id &&
          held.session != null &&
          held.session == left.session;
      return (
        arrived,
        [
          ...effects,
          if (silent) ...const [_watch, ReturnToThePanorama()],
          if (!silent) OpenThePanorama(id, left.language),
        ],
      );
    case LeftEntry(panorama: false, book: _?):
      return (machine, [EnterThePassageLeft(left)]);
    default:
      return (machine, const []);
  }
}

(Machine, List<Effect>) _reachTheStation(Machine machine, StationEvent event) {
  final next = machine.station.answer(event);
  if (next == machine.station) return (machine, const []);
  final carriesTheSceneTurn =
      event is TheSceneRehearsalLeft && machine.holdsATurn;
  final arrived = (carriesTheSceneTurn ? machine : moveTheGeneration(machine))
      .copyWith(
        station: next,
        wordlessTelling: false,
        letTheWaitingHaltGo: true,
      );
  if (machine.aHaltWaitsForTheCanvas case final waiting? when next is Canvas) {
    return _theHalt(arrived, waiting);
  }
  return (arrived, const []);
}

bool _silent(Machine machine) =>
    machine.halt is! Blocking &&
    (machine.channel is Silence || machine.channel is Paused);

bool _own(Machine machine, Line line) =>
    (machine.owners[line] ?? const <int>{}).any(machine.onTheirWay.contains);

Line? _nextLine(Machine machine) {
  if (!_silent(machine)) return null;
  for (final line in machine.queue) {
    if (_own(machine, line)) return line;
  }
  if (machine.onTheirWay.isNotEmpty || machine.queue.isEmpty) return null;
  return machine.queue.first;
}

Paused? _heldBy(Channel channel) => switch (channel) {
  final Paused paused => paused,
  Microphone(:final held) || GuideSpeaking(:final held) => held,
  _ => null,
};

(Machine, List<Effect>) _say(Machine machine, Line line) => (
  machine.copyWith(
    channel: GuideSpeaking(line, held: _heldBy(machine.channel)),
    queue: [...machine.queue.where((waiting) => waiting != line)],
    owners: {...machine.owners}..remove(line),
  ),
  [PlayLine(line)],
);

(Machine, List<Effect>) _drain(
  Machine machine, [
  List<Effect> before = const [],
]) {
  final next = _nextLine(machine);
  if (next == null) return (machine, before);
  final (said, effects) = _say(machine, next);
  return (said, [...before, ...effects]);
}

(Machine, List<Effect>) _arrive(Machine machine, Line line, List<int> by) {
  final own = by.any(machine.onTheirWay.contains);
  if (!own &&
      machine.queue.any(
        (waiting) => waiting.kind == line.kind && !_own(machine, waiting),
      )) {
    return (machine, [DropTheLine(line)]);
  }
  final (heard, stopped) = _theReplyGivesWayTo(machine, line);
  return _drain(
    heard.copyWith(
      queue: [...heard.queue, line],
      owners: own ? {...heard.owners, line: by.toSet()} : null,
    ),
    stopped,
  );
}

(Machine, List<Effect>) _theReplyGivesWayTo(Machine machine, Line line) =>
    switch (machine.channel) {
      GuideSpeaking(line: final reply, :final held)
          when reply.kind == LineKind.reply && line.kind != LineKind.reply =>
        (
          machine.copyWith(channel: held ?? const Silence()),
          [StopTheLine(reply)],
        ),
      _ => (machine, const []),
    };

(Machine, List<Effect>) _leaveTheQueue(
  Machine machine,
  bool Function(Line) leaves,
) => (
  machine.copyWith(queue: [...machine.queue.where((line) => !leaves(line))]),
  [
    for (final line in machine.queue)
      if (leaves(line)) DropTheLine(line),
  ],
);

Line? _speaking(Channel channel) => switch (channel) {
  GuideSpeaking(:final line) => line,
  _ => null,
};

bool _speaks(Machine machine, Line line) => _speaking(machine.channel) == line;

bool _sounds(Machine machine, Sound sound, {bool orHeld = false}) =>
    switch (machine.channel) {
      Playing(sound: final playing) => playing == sound,
      Paused(:final what) => orHeld && what == sound,
      _ => false,
    };

/// A line's answer reaches the Channel only while that line is the one speaking; the
/// gesture that waits on it is told how it ended either way.
(Machine, List<Effect>) _answer(
  Machine machine,
  Line line,
  Said said, {
  Exception? because,
  required (Machine, List<Effect>) Function() heard,
  (Machine, List<Effect>) Function()? unheard,
}) {
  final speaking = _speaks(machine, line);
  final (next, effects) = speaking
      ? heard()
      : unheard?.call() ?? (machine, const <Effect>[]);
  return (
    next.copyWith(
      lastLine: speaking
          ? LineOutcome(line, said, because: because)
          : LineOutcome(line, said == Said.said ? Said.said : Said.unsaid),
    ),
    effects,
  );
}

(Machine, List<Effect>) _notSaid(Machine machine, Line line) =>
    switch (machine.channel) {
      GuideSpeaking(line: final speaking, :final held) when speaking == line =>
        _drain(machine.copyWith(channel: held ?? const Silence())),
      _ => _leaveTheQueue(machine, (waiting) => waiting == line),
    };

Machine _opened(Machine machine) => switch (machine.channel) {
  final Playing playing => machine.copyWith(
    channel: _playing(
      playing.sound,
      opened: true,
      next: playing.next,
      held: playing.held,
    ),
  ),
  final Paused paused => machine.copyWith(channel: _openedUnder(paused)),
  GuideSpeaking(:final line, :final held) => machine.copyWith(
    channel: GuideSpeaking(line, held: _openedUnder(held)),
  ),
  Microphone(:final owner, :final held, :final cut) => machine.copyWith(
    channel: Microphone(owner, held: _openedUnder(held), cut: cut),
  ),
  _ => machine,
};

Paused? _openedUnder(Paused? paused) => switch (paused) {
  Paused(:final what, :final next, :final held, started: true, opened: false) =>
    Paused(what, next: next, held: held),
  _ => paused,
};

(Machine, List<Effect>) _theReplyFailed(
  Machine machine,
  TheReplyFailedToLoad failed,
) => switch (FailurePolicy.decideOnTheTablet(
  failed.failure,
  FailureContext(
    station: machine.station,
    generation: machine.generation,
    sounding: failed.sounding,
  ),
)) {
  TheRefusalPassed() => (machine, [LoadTheReplyAgain(failed.answered)]),
  final decided => switch (reduce(machine, decided)) {
    (final next, final effects) => (
      next,
      [...effects, LetTheReplyGo(failed.answered, decided: decided)],
    ),
  },
};

(Machine, List<Effect>) _ended(Machine machine) {
  switch (machine.channel) {
    case GuideSpeaking(:final held):
      return _drain(machine.copyWith(channel: held ?? const Silence()));
    case final Playing playing:
      if (playing.next.isNotEmpty) {
        return _start(machine, playing.next, playing.held);
      }
      return _drain(machine.copyWith(channel: playing.held ?? const Silence()));
    case Paused(:final next, :final held) when next.isNotEmpty:
      return (
        machine.copyWith(
          channel: Paused(
            next.first,
            next: next.skip(1).toList(),
            started: false,
            held: held,
          ),
        ),
        const [],
      );
    case Paused(:final held):
      return _drain(machine.copyWith(channel: held ?? const Silence()));
    default:
      return (machine, const []);
  }
}

Machine _silenced(Machine machine, bool keepingTheHold) =>
    switch (machine.channel) {
      Microphone() => machine,
      Paused() when keepingTheHold => machine,
      GuideSpeaking(:final held) when keepingTheHold => machine.copyWith(
        channel: held ?? const Silence(),
      ),
      _ => machine.copyWith(channel: const Silence()),
    };

(Machine, List<Effect>) _failed(Machine machine) {
  final channel = machine.channel;
  return _drain(
    machine.copyWith(
      channel: switch (channel) {
        GuideSpeaking(:final held) => held ?? const Silence(),
        Playing(:final held) => held ?? const Silence(),
        _ => channel,
      },
    ),
  );
}

(Machine, List<Effect>) _tellThePlayFailed(Machine machine) {
  final (failed, effects) = _failed(machine);
  return (failed, [...effects, const TellThePlayFailed()]);
}

(Machine, List<Effect>) _openTheMic(
  Machine machine,
  MicOwner owner,
  String take,
) {
  if (!_silent(machine)) return (machine, const []);
  return (
    machine.copyWith(
      channel: Microphone(owner, held: _keptUnderTheMic(machine.channel)),
      wordlessTelling: machine.wordlessTelling && owner != MicOwner.capture,
    ),
    [OpenTheMic(owner, take: take)],
  );
}

Paused? _keptUnderTheMic(Channel channel) => switch (channel) {
  Paused(what: PartSound()) => channel,
  Paused(held: final part) => part,
  _ => null,
};

/// The team's tap while the Guide speaks on the Canvas or the Panorama: her line ends
/// cut, and the conversation's microphone opens in the same step, after the stop. Over the
/// acknowledgement, the reply waiting behind it is the line cut, at its very start.
(Machine, List<Effect>) _interrupt(
  Machine machine,
  String take,
  CutPoint measured,
) {
  if ((machine.station is! Canvas && machine.station is! Panorama) ||
      machine.halt is Blocking) {
    return (machine, const []);
  }
  final (reply, held, cut) = switch (machine.channel) {
    GuideSpeaking(
      line: Line(kind: LineKind.guide || LineKind.approved) && final line,
      :final held,
    ) =>
      (line, held, measured),
    GuideSpeaking(line: Line(kind: LineKind.acknowledgement), :final held) => (
      machine.queue.where((line) => line.kind == LineKind.guide).firstOrNull,
      held,
      const CutPoint(Duration.zero),
    ),
    _ => (null, null, null),
  };
  if (reply == null) return (machine, const []);
  return (
    machine.copyWith(
      channel: Microphone(
        MicOwner.conversation,
        held: _keptUnderTheMic(held ?? const Silence()),
        cut: cut,
      ),
      queue: [...machine.queue.where((line) => line != reply)],
      owners: {...machine.owners}..remove(reply),
      lastLine: LineOutcome(reply, Said.cut),
    ),
    [const StopTheSound(), OpenTheMic(MicOwner.conversation, take: take)],
  );
}

(Machine, List<Effect>) _closeTheMic(Machine machine) =>
    switch (machine.channel) {
      Microphone(:final held) => _drain(
        machine.copyWith(channel: held ?? const Silence()),
      ),
      _ => (machine, const []),
    };

/// Every answer but a start, or a recorder that failed to stop, gives the Channel back, as
/// a closed microphone does.
(Machine, List<Effect>) _heard(
  Machine machine,
  MicAnswer answer,
  String? take,
  Object? because,
  MicOwner? owner,
) {
  final theirs = switch (machine.channel) {
    Microphone(owner: final open) =>
      answer != MicAnswer.closed || owner == null || owner == open,
    _ => true,
  };
  final (
    answered,
    effects,
  ) = answer == MicAnswer.started || because != null || !theirs
      ? (machine, const <Effect>[])
      : _closeTheMic(machine);
  return (
    answered.copyWith(
      lastMic: MicOutcome(
        answer,
        take: take,
        because: because,
        owner: owner,
        cut: switch ((answer, machine.channel)) {
          (MicAnswer.closed, Microphone(:final cut)) when theirs => cut,
          _ => null,
        },
      ),
    ),
    effects,
  );
}

(Machine, List<Effect>) _discardTheMic(Machine machine) {
  final (closed, effects) = _closeTheMic(machine);
  return (closed, [const DiscardTheMic(), ...effects]);
}

(Machine, List<Effect>) _tapped(
  Machine machine,
  List<Sound> sounds,
  Paused? beneath,
) {
  if (machine.halt is Blocking ||
      machine.channel is Microphone ||
      sounds.isEmpty) {
    return (machine, const []);
  }
  final (started, effects) = _start(machine, sounds, beneath);
  return (started, [..._stopTheLineIn(machine.channel), ...effects]);
}

(Machine, List<Effect>) _start(
  Machine machine,
  List<Sound> sounds, [
  Paused? held,
]) {
  final sound = sounds.first;
  return (
    machine.copyWith(
      channel: _playing(sound, next: sounds.skip(1).toList(), held: held),
    ),
    [_play(sound)],
  );
}

Effect _play(Sound sound) => switch (sound) {
  final PartSound part => PlayPart(part),
  final StretchSound stretch => PlayStretch(stretch),
};

Playing _playing(
  Sound sound, {
  bool opened = false,
  List<Sound> next = const [],
  Paused? held,
}) => switch (sound) {
  final PartSound part => PartPlaying(
    part,
    opened: opened,
    next: next,
    held: held,
  ),
  final StretchSound stretch => StretchPlaying(
    stretch,
    opened: opened,
    next: next,
    held: held,
  ),
};

(Machine, List<Effect>) _resumeFromUnder(Machine paused, Line line) {
  final (resumed, effects) = _pause(paused);
  return (resumed, [StopTheLine(line), ...effects]);
}

List<Effect> _stopTheLineIn(Channel channel) => switch (channel) {
  GuideSpeaking(:final line) => [StopTheLine(line)],
  _ => const [],
};

(Machine, List<Effect>) _pause(Machine machine) => switch (machine.channel) {
  GuideSpeaking(:final line, held: final Paused paused) => _resumeFromUnder(
    machine.copyWith(channel: paused),
    line,
  ),
  final Playing playing => (
    machine.copyWith(
      channel: Paused(
        playing.sound,
        next: playing.next,
        held: playing.held,
        opened: playing.opened,
      ),
    ),
    const [HoldTheSound()],
  ),
  Paused(:final what, :final next, :final held, :final opened, started: true) =>
    (
      machine.copyWith(
        channel: _playing(what, opened: opened, next: next, held: held),
      ),
      const [LetTheSoundRun()],
    ),
  Paused(:final what, :final next, :final held) => (
    machine.copyWith(
      channel: _playing(what, next: next, held: held),
    ),
    [_play(what)],
  ),
  _ => (machine, const []),
};

(Machine, List<Effect>) _theHalt(Machine machine, MachineEvent event) {
  final (halt, effects) = _reduceTheHalt(machine.halt, event);
  final next = machine.copyWith(halt: halt);
  if (halt is Blocking && machine.halt is! Blocking) {
    return (
      next.copyWith(
        channel: const Silence(),
        look: machine.look?.copyWith(suspended: true),
      ),
      [...effects, if (machine.look != null) const StopLooking()],
    );
  }
  if (halt is! Blocking && machine.halt is Blocking) {
    final (rested, resumed) = _resumeTheLook(next);
    return _drain(rested, [...effects, ...resumed]);
  }
  return (next, effects);
}

/// A look a halt held back goes on once the room is no longer halted, under the busy
/// watchdog again.
(Machine, List<Effect>) _resumeTheLook(Machine machine) {
  final look = machine.look;
  if (look == null || !look.suspended || machine.halt is Blocking) {
    return (machine, const []);
  }
  return (
    machine.copyWith(look: look.copyWith(suspended: false, asked: true)),
    [
      if (!look.asked) LookAtTheSession(look.turn, sounding: look.sounding),
      if (look.stillAnswering) LookAgain(look.turn, sounding: look.sounding),
      const ResumeTheWait(),
    ],
  );
}

Machine _land(Machine machine, Turn turn) =>
    machine.inFlight == turn ? machine.copyWith(landTheTurn: true) : machine;

(Machine, List<Effect>) _giveUp(Machine machine, Turn turn, Kept sounding) {
  if (machine.inFlight != turn) return (machine, const []);
  final halted = machine.halt is Blocking;
  return (
    machine.copyWith(
      landTheTurn: true,
      look: TheLook(
        turn,
        sounding: sounding,
        asked: !halted,
        suspended: halted,
      ),
    ),
    [
      LetTheTurnGo(turn),
      if (!halted) LookAtTheSession(turn, sounding: sounding),
    ],
  );
}

(Machine, List<Effect>) _theSessionGone(Machine machine) => (
  _leftThePassage(machine, const NoHalt()),
  [
    ..._leavingThePassage(machine),
    const DiscardTheSession(),
    const OpenTheChoice(),
  ],
);

/// A resume that failed keeps its session, so the next open of the passage asks again
/// (ADR 0064), and so does the warning the session holds.
(Machine, List<Effect>) _theResumeFailed(Machine machine) => _orBackToWhatWaits(
  _leftThePassage(machine, switch (machine.halt) {
    Warning() || Blocking(warningBeneath: true) => const Warning(),
    _ => const NoHalt(),
  }),
  _leavingThePassage(machine),
  const OpenTheChoice(),
);

Machine _leftThePassage(Machine machine, Halt halt) => machine.copyWith(
  halt: halt,
  channel: const Silence(),
  queue: const [],
  owners: const {},
  letTheWaitingHaltGo: true,
);

List<Effect> _leavingThePassage(Machine machine) => [
  const StopTheSound(),
  const CloseAndDiscardTheMic(),
  for (final line in machine.queue) DropTheLine(line),
];

(Halt, List<Effect>) _reduceTheHalt(
  Halt halt,
  MachineEvent event,
) => switch (event) {
  SessionRead() => _read(halt, event),
  RoomRaisedAHalt(:final callsForAPerson) => switch (halt) {
    Blocking(:final warningBeneath, callsNobody: true) when callsForAPerson => (
      Blocking(warningBeneath: warningBeneath),
      const [CallForAPerson(), _watch],
    ),
    Blocking() => (halt, [if (callsForAPerson) const CallForAPerson(), _watch]),
    _ => (
      Blocking(warningBeneath: halt is Warning, callsNobody: !callsForAPerson),
      [..._enter, if (callsForAPerson) const CallForAPerson(), _watch],
    ),
  },
  TheAnswerWarned() => switch (halt) {
    Blocking(:final callsNobody) => (
      Blocking(warningBeneath: true, callsNobody: callsNobody),
      const [_watch],
    ),
    _ => (const Warning(), const [_watch]),
  },
  TeamTapped() => switch (halt) {
    Blocking(:final warningBeneath, callsNobody: true) => (
      warningBeneath ? const Warning() : const NoHalt(),
      const [StopCallingForAPerson(), _watch],
    ),
    Blocking(:final warningBeneath) => (
      warningBeneath ? const Warning() : const NoHalt(),
      const [StopCallingForAPerson(), GoOnAfterTheSign(), _watch],
    ),
    _ => (halt, const []),
  },
  WatchFired() => (halt, const [ReadTheState(), _watch]),
  NetworkFailedAt() ||
  TheRoomAnswered() ||
  OutboxChanged() ||
  ATakeLeft() ||
  ATakeSettled() ||
  AKeepBegan() ||
  AKeepEnded() ||
  TheTapSent() ||
  StopTapped() ||
  LineArrived() ||
  PlayerOpened() ||
  PlayerEnded() ||
  PlayerFailed() ||
  MicOpened() ||
  MicClosed() ||
  MicAnswered() ||
  MicClosing() ||
  MicDiscarded() ||
  BeadTapped() ||
  PauseTapped() ||
  TheHeldPartReturns() ||
  GestureSilenced() ||
  Interrupted() ||
  GestureStarted() ||
  GestureEnded() ||
  LineNotSaid() ||
  StepLeft() ||
  LeftThePassage() ||
  TheSessionIsGone() ||
  ThePassageClosed() ||
  TurnGivenUp() ||
  LookFound() ||
  LookEmpty() ||
  LookFailed() ||
  LookPending() ||
  TheOpeningMissed() ||
  TheReplyFailedToLoad() ||
  ThePassageCannotOpen() ||
  TheTellingCameBackEmpty() ||
  TheStepFailed() ||
  TheResumeFailed() ||
  TheSceneTurnFoundNothing() ||
  TheVerdictAsked() ||
  TheTranslationStartedOver() ||
  TurnSent() ||
  TurnAnswered() ||
  TurnFailed() ||
  TheRefusalPassed() ||
  TheHandFailed() ||
  TheScenesMissed() ||
  TheSceneDoorFailed() ||
  TheSceneWentAlready() ||
  TheSceneSendRefused() ||
  TheSceneDiskFailed() ||
  TheSceneRehearsalsListed() ||
  TheCallWasRefused() ||
  TheCallMetAClosedPassage() ||
  StationEvent() ||
  TheLanguageChosen() ||
  TheRehearsalWeighed() ||
  ThePanoramaAsked() ||
  TheSessionOpened() ||
  ThePanoramaFound() ||
  TheSessionLetGo() ||
  TheWayBackTaken() ||
  TheEntryWaits() ||
  TheOpenBroughtNoSession() ||
  TheLeftPassageReturns() => (halt, const []),
};

/// A read never raises the person sign nor clears it: over none it applies its warning
/// only, and under the sign the warning beneath (ADR 0093, 0107).
(Halt, List<Effect>) _read(Halt halt, SessionRead read) {
  final snapshot = read.snapshot;
  final warns = snapshot.halt == HaltKind.warning;
  if (halt is Blocking) {
    return (
      snapshot.needsPerson
          ? Blocking(warningBeneath: halt.warningBeneath)
          : Blocking(warningBeneath: warns, callsNobody: halt.callsNobody),
      const [_watch],
    );
  }
  final Halt told = snapshot.needsPerson
      ? halt
      : warns
      ? const Warning()
      : const NoHalt();
  return switch ((halt, told)) {
    (NoHalt(), NoHalt()) => (halt, const []),
    _ => (told, const [_watch]),
  };
}
