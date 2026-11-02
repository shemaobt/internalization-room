import 'package:internalization_room/features/sala/data/raised_hand.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

class AHandHost implements HandHost {
  List<HandReply> replies = const [];
  String? playingReplyId;
  Channel channel = const Silence();
  bool noteMode = false;
  VoiceState voice = VoiceState.invite;
  String? stationSessionId = 'sessao-1';
  bool atTheTeamsIdleTurn = true;
  bool aQuestionRecords = false;

  final List<String> written = [];
  final List<List<HandReply>> shown = [];
  final List<List<HandReply>> markedHeard = [];
  final List<Future<void>> handedOff = [];

  @override
  HandView get view => (
    replies: replies,
    playingReplyId: playingReplyId,
    channel: channel,
    noteMode: noteMode,
    voice: voice,
    stationSessionId: stationSessionId,
    atTheTeamsIdleTurn: atTheTeamsIdleTurn,
    aQuestionRecords: aQuestionRecords,
    oldestUnheardReply: replies.where((reply) => reply.offered).firstOrNull,
  );

  @override
  void showReplies(List<HandReply> replies) {
    written.add('showReplies');
    shown.add(replies);
    this.replies = replies;
  }

  @override
  void markPlaying(String id) {
    written.add('markPlaying:$id');
    playingReplyId = id;
  }

  @override
  void clearPlaying() {
    written.add('clearPlaying');
    playingReplyId = null;
  }

  @override
  void markReplyHeard(List<HandReply> replies) {
    written.add('markReplyHeard');
    markedHeard.add(replies);
    this.replies = replies;
    playingReplyId = null;
  }

  @override
  void enterNoteMode() {
    written.add('enterNoteMode');
    noteMode = true;
  }

  @override
  void leaveNoteMode() {
    written.add('leaveNoteMode');
    noteMode = false;
  }

  @override
  bool gone = false;

  @override
  int? get thisLife => null;

  @override
  bool endedSince(int? life) => false;

  @override
  bool abandoned(int generation) => false;

  @override
  int get waitOnTheGeneration => 0;

  @override
  String stamp() => 'carimbo';

  @override
  bool theGuardKeeps(String path) => true;

  @override
  void dispatch(MachineEvent event) {}

  @override
  void decideAt(RoomFailure failure, {required Door door}) {}

  @override
  void handOff(Future<void> next) => handedOff.add(next);

  @override
  void silenceTheRoom() {}

  @override
  void startListening(String fileName, {required MicOwner owner}) {}

  @override
  Future<MicOutcome> closeTheMicrophone() async =>
      const MicOutcome(MicAnswer.closed);

  @override
  Future<Said> sayTheLine(LineKind kind, {String? url, Source? source}) async =>
      Said.said;
}
