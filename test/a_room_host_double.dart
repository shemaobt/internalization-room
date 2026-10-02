import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

class ARoomHost implements EffectHost {
  final List<String> asked = [];
  final List<MachineEvent> answers = [];
  void Function(MachineEvent event)? onAnswer;

  @override
  bool watchIsWanted = true;

  @override
  bool roomIsReachable = true;

  @override
  void answer(MachineEvent event) {
    answers.add(event);
    onAnswer?.call(event);
  }

  @override
  void silenceTheRoom() => asked.add('silenceTheRoom');

  @override
  void closeAndDiscardTheMic({required bool wasOpen}) =>
      asked.add('closeAndDiscardTheMic');

  @override
  void callForAPerson() => asked.add('callForAPerson');

  @override
  void stopCallingForAPerson() => asked.add('stopCallingForAPerson');

  @override
  void tellAPersonArrived() => asked.add('tellAPersonArrived');

  @override
  void readTheState() => asked.add('readTheState');

  @override
  void replayTheSound(Kept kept) => asked.add('replayTheSound');

  @override
  void askTheOpeningAgain(String freshTurnId) =>
      asked.add('askTheOpeningAgain');

  @override
  void playLine(Line line) => asked.add('playLine');

  @override
  void thePartIsInTheAir() => asked.add('thePartIsInTheAir');

  @override
  void openTheMic(String take) => asked.add('openTheMic');

  @override
  void dropTheLine(Line line) => asked.add('dropTheLine');

  @override
  void holdTheSound() => asked.add('holdTheSound');

  @override
  void letTheSoundRun() => asked.add('letTheSoundRun');

  @override
  void drainTheOutbox() => asked.add('drainTheOutbox');

  @override
  void resendPending() => asked.add('resendPending');

  @override
  void probeTheRoom() => asked.add('probeTheRoom');

  @override
  void discardTheSession() => asked.add('discardTheSession');

  @override
  void openTheChoice() => asked.add('openTheChoice');

  @override
  void sayTheOfflineNotice() => asked.add('sayTheOfflineNotice');
}
