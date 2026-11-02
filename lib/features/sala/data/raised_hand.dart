import 'dart:async';
import 'dart:io';

import '../domain/channel.dart';
import '../domain/hand_reply.dart';
import '../domain/machine.dart';
import '../domain/session_state.dart';
import 'hand_inbox_repository.dart';
import 'recording_repository.dart';
import 'room_answer.dart';

/// What the hand reads of the room, as the room stands when it is asked.
typedef HandView = ({
  List<HandReply> replies,
  String? playingReplyId,
  Channel channel,
  bool noteMode,
  VoiceState voice,
  String? stationSessionId,
  bool atTheTeamsIdleTurn,
  bool aQuestionRecords,
  HandReply? oldestUnheardReply,
});

abstract interface class HandHost {
  /// The room as the hand reads it now, holding the very replies the hand last wrote.
  HandView get view;

  void showReplies(List<HandReply> replies);

  void markPlaying(String id);

  void clearPlaying();

  /// The room shows [replies], one of them now heard, and the hand is lit on no reply.
  void markReplyHeard(List<HandReply> replies);

  void enterNoteMode();

  void leaveNoteMode();

  bool get gone;

  int? get thisLife;

  bool endedSince(int? life);

  bool abandoned(int generation);

  int get waitOnTheGeneration;

  String stamp();

  bool theGuardKeeps(String path);

  void dispatch(MachineEvent event);

  void decideAt(RoomFailure failure, {required Door door});

  void handOff(Future<void> next);

  void silenceTheRoom();

  void startListening(String fileName, {required MicOwner owner});

  Future<MicOutcome> closeTheMicrophone();

  Future<Said> sayTheLine(LineKind kind, {String? url, Source? source});
}

class RaisedHand {
  final HandHost host;
  final HandInboxRepository Function() inbox;
  final RecordingRepository Function() recorder;

  RaisedHand({required this.host, required this.inbox, required this.recorder});

  Future<void>? _inboxRead;

  bool _sendingAQuestion = false;

  final _failures = <(String, String), int>{};

  HandView get _state => host.view;

  Future<void> pull() {
    if (_inboxRead case final reading?) return reading;
    late final Future<void> reading;
    reading = _readTheInbox().whenComplete(() {
      if (identical(_inboxRead, reading)) _inboxRead = null;
    });
    return _inboxRead = reading;
  }

  Future<void> _readTheInbox() async {
    final life = host.thisLife;
    final List<HandReply> fetched;
    switch (await inbox().fetchReplies()) {
      case Answered(:final value):
        fetched = value;
      case final RoomFailure failure:
        if (host.endedSince(life)) return;
        return host.decideAt(failure, door: Door.inbox);
    }
    if (host.endedSince(life)) return;
    final known = {for (final reply in _state.replies) reply.id: reply};
    // The desk does re-send audio_url for a question_id it already served: a reply the
    // facilitator records again supersedes the first under a new content-hashed key and
    // comes back unheard, while the old address stops answering. Keeping the first
    // address seen played a 404 and marked the new reply heard without a sound.
    final merged = [
      for (final reply in fetched)
        switch (known[reply.id]) {
          final kept? when kept.audioUrl == reply.audioUrl => kept,
          _ => _tallied(reply),
        },
    ];
    if (_sameReplies(merged, _state.replies)) return;
    host.showReplies(merged);
  }

  bool _sameReplies(List<HandReply> a, List<HandReply> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].audioUrl != b[i].audioUrl) return false;
    }
    return true;
  }

  void tap() {
    if (_state.aQuestionRecords) return cancelQuestion();
    if (_sendingAQuestion) return;
    if (!_state.atTheTeamsIdleTurn) return;
    if (_state.playingReplyId != null || _state.channel is PartPlaying) {
      host.silenceTheRoom();
    }
    if (_state.noteMode) {
      cancelQuestion();
      return;
    }
    final unheard = _state.oldestUnheardReply;
    if (unheard != null) {
      host.markPlaying(unheard.id);
      host.handOff(_playReply(unheard));
      return;
    }
    host.enterNoteMode();
  }

  /// The circle's half of a question: it opens the microphone once the hand has armed
  /// the note, and closes and sends it on the touch after that.
  ///
  /// Splitting this off the hand is what keeps a question from ever starting under the
  /// facilitator's own voice — arming and recording used to be the same touch, so the
  /// first tap was already capturing whatever the facilitator was mid-sentence saying.
  void noteTap() {
    switch (_state.voice) {
      case VoiceState.invite:
      case VoiceState.done:
        host.startListening(
          'pergunta_${host.stamp()}',
          owner: MicOwner.question,
        );
      case VoiceState.listening:
        _sendQuestion();
      case VoiceState.thinking:
      case VoiceState.speaking:
        break;
    }
  }

  /// Play the facilitator's answer, and let it go only once it has been heard.
  ///
  /// A reply is marked heard when the player reported the whole clip. A clip that cannot
  /// be decoded, is cut short, or never arrives stays unheard.
  ///
  /// It is offered again on the next touch of the hand, and the second failure at the
  /// same address, a sound that did not play or a mark the desk refused, sets it aside on
  /// the tablet: it stops counting as unheard, so the hand plays the next reply or arms a
  /// question. A clip that never decodes is served from the tablet's copy every time and
  /// would otherwise hold the gesture until the facilitator records it again. Nothing is
  /// marked for a sound that did not play, and the desk keeps showing the reply as not
  /// heard. The inbox is read again on the failure, as it is after a refused mark, and a
  /// reply recorded again arrives at its new address with no failures, which is what
  /// lifts the set-aside.
  ///
  /// A room that cannot serve the clip is not set aside: the Failure policy decides it at the
  /// reply door, where it changes nothing in the room (ADR 0071), and the reply keeps its dot
  /// for the next touch.
  ///
  /// The playing mark is given back on every way out. `_markHeard` is what clears it when
  /// the reply sounded; a reply that did not, or that outlived its generation, clears it
  /// here, or the hand stays lit on it for good. A reply stopped by the hand to be played
  /// again leaves the mark, and the heard mark, to the play that took its place, whatever
  /// the player reports of the stopped one.
  Future<void> _playReply(HandReply reply) async {
    Said said;
    try {
      said = await host.sayTheLine(
        LineKind.reply,
        url: reply.audioUrl,
        source: Source.reply(reply.id),
      );
    } on NetworkFailed catch (failure) {
      if (_state.playingReplyId == reply.id) host.clearPlaying();
      return host.decideAt(failure, door: Door.reply);
    } on Exception {
      said = Said.failed;
    }
    if (host.gone || _aReplySounds) return;
    final current =
        said != Said.unsaid &&
        !_state.replies.any(
          (kept) => kept.id == reply.id && kept.audioUrl != reply.audioUrl,
        );
    if (said == Said.said && current) {
      unawaited(_markHeard(reply));
      return;
    }
    if (_state.playingReplyId == reply.id) host.clearPlaying();
    if (current) {
      host.showReplies(_unsounded(reply));
      unawaited(pull());
    }
  }

  bool get _aReplySounds => switch (_state.channel) {
    GuideSpeaking(line: Line(kind: LineKind.reply)) => true,
    _ => false,
  };

  List<HandReply> _unsounded(HandReply reply) {
    final count = _fail(reply);
    return _replies(
      (kept) => _sameClip(kept, reply),
      (kept) => kept.withFailures(count),
    );
  }

  int _fail(HandReply reply) => _failures.update(
    (reply.id, reply.audioUrl),
    (count) => count + 1,
    ifAbsent: () => 1,
  );

  HandReply _tallied(HandReply reply) =>
      reply.withFailures(_failures[(reply.id, reply.audioUrl)] ?? 0);

  bool _sameClip(HandReply a, HandReply b) =>
      a.id == b.id && a.audioUrl == b.audioUrl;

  /// A reply is heard when the desk agrees, and not before.
  ///
  /// The mark was made on the tablet whatever the desk answered, and it survives only as
  /// long as the screen does: rebuilt state reads the reply back from the desk, which
  /// never learned, and the team is played the same answer again. Leaving it unheard is
  /// the honest state: it is offered again, until a second failure sets it aside.
  ///
  /// No retry. The precedent for a call that must land is the one that asks for a person,
  /// and it retries because nobody comes if it is lost. Nothing is lost here: the reply
  /// stays in the desk's list and the next tap plays it and marks it again. An unbounded retry on
  /// bookkeeping buys nothing and is not free.
  ///
  /// The mark and the gesture move together, and the mark is taken back if the desk
  /// disagrees. Releasing the gesture first and marking afterwards opened a window as long
  /// as the request: the hand was free again while the reply still read as unheard, so a
  /// second touch played the same answer to the team and sent a second mark. That is the
  /// replay this whole change exists to stop, through a door of its own making.
  ///
  /// The other way to close it was to hold the gesture until the desk answered, and it
  /// costs more than it saves: up to the full timeout with the hand dead, and the hand is
  /// the team's only one — they could not even raise a question meanwhile. This way the
  /// room is briefly optimistic, for as long as one request, and corrects itself. That is
  /// a different animal from the optimism this slice removes, which outlived the request
  /// and died only with the screen, leaving the desk to contradict it on the next start.
  ///
  /// A refusal also pulls the inbox. The one refusal the desk makes on purpose is that the
  /// reply moved on: the facilitator recorded again while this one played, and the address
  /// the tablet holds has stopped answering. The inbox is otherwise read thirty seconds
  /// after a turn, and not at all while the room sits on the Choice, so without this pull
  /// the hand kept offering a clip that sounds nothing and marks nothing. A refusal counts
  /// as a failure of the reply at the address that was marked; an outage counts nothing.
  /// Both pull; a pull is one GET, and after an outage it changes nothing.
  Future<void> _markHeard(HandReply marked) async {
    final life = host.thisLife;
    HandReply? heard;
    host.markReplyHeard(
      _replies(
        (kept) => _sameClip(kept, marked),
        (kept) => heard = kept.asHeard(),
      ),
    );
    final RoomFailure failure;
    switch (await inbox().markHeard(marked.id, audioUrl: marked.audioUrl)) {
      case Answered():
        return;
      case final RoomFailure refused:
        failure = refused;
    }
    host.decideAt(failure, door: Door.inbox);
    if (host.endedSince(life)) return;
    host.showReplies(
      failure is Refused
          ? _refused(marked, heard)
          : _replies(
              (kept) => identical(kept, heard),
              (kept) => kept.asUnheard(),
            ),
    );
    unawaited(pull());
  }

  List<HandReply> _refused(HandReply marked, HandReply? heard) {
    final count = _fail(marked);
    return _replies(
      (kept) => _sameClip(kept, marked),
      (kept) => (identical(kept, heard) ? kept.asUnheard() : kept).withFailures(
        count,
      ),
    );
  }

  List<HandReply> _replies(
    bool Function(HandReply) which,
    HandReply Function(HandReply) change,
  ) => [
    for (final kept in _state.replies)
      if (which(kept)) change(kept) else kept,
  ];

  void cancelQuestion() {
    host.dispatch(const MicDiscarded());
    host.leaveNoteMode();
  }

  void _sendQuestion() {
    if (!_state.noteMode) return;
    host.leaveNoteMode();
    _sendingAQuestion = true;
    host.handOff(
      _deliver(host.thisLife).whenComplete(() => _sendingAQuestion = false),
    );
  }

  Future<void> _deliver(int? life) async {
    final generation = host.waitOnTheGeneration;
    final sessionId = _state.stationSessionId;
    final path = (await host.closeTheMicrophone()).take;
    if (path == null ||
        host.endedSince(life) ||
        !host.theGuardKeeps(path) ||
        sessionId == null) {
      if (path != null) unawaited(recorder().delete(path));
      return;
    }
    final kept = recorder();
    final RoomAnswer<void> sent;
    try {
      sent = await inbox().sendQuestion(sessionId, File(path));
    } on FileSystemException {
      return;
    }
    switch (sent) {
      case Answered():
        unawaited(kept.delete(path));
      case final RoomFailure failure:
        if (host.abandoned(generation)) return;
        host.decideAt(failure, door: Door.question);
    }
  }
}
