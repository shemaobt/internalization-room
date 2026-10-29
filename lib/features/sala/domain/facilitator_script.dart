import 'dart:math';

import 'moment.dart';
import 'scene_rehearsal.dart';

const languages = ['pt', 'en'];

const floorLanguage = 'pt';

const instantAckLines = ['F0', 'F1', 'F2'];

const startLine = 'P0';

const tellLine = 'P1';

/// The first of her Ensaio Final lines, read by position from her N block: said as the
/// First listen opens on a Joined recording.
const firstListenLine = 'N0';

/// The third of Marcia's process lines, read by position: start, tell, unheard,
/// approved. Said when a part recorded again leaves some of the rehearsal still heard.
const unheardLine = 'P2';

/// The fourth of Marcia's process lines, read by position: start, tell, unheard,
/// approved. The approval's is the fourth, never rotated.
const approvedLine = 'P3';

/// The first of Marcia's external-check lines, read by position: open, retell, whole,
/// frases, thanks. Its second sentence is the consent.
const listenerOpenLine = 'X0';

/// The second of Marcia's external-check lines, read by position: open, retell, whole,
/// frases, thanks. Said once the whole passage ended, before the circle opens.
const listenerRetellLine = 'X1';

/// The last of Marcia's external-check lines, her thanks as a listener ends.
const listenerThanksLine = 'X4';

const sentenceInPlaceLine = 'N4';

const sentenceAwaitingLine = 'N5';

const sentenceListenLine = 'N6';

const sentenceRecordLine = 'N7';

/// Marcia's pick: any acknowledgement but the one said last.
int acknowledgementAfter(int last, Random random) =>
    (last + 1 + random.nextInt(instantAckLines.length - 1)) %
    instantAckLines.length;

const circleLabels = {
  'default': {'pt': 'Toque para falar', 'en': 'Tap to speak'},
};

String circleLabelFor(String state, String language) =>
    circleLabels[state]![language] ?? circleLabels[state]![floorLanguage]!;

const handLabels = {
  'hearTheAnswer': {
    'pt': 'Ouvir a resposta do facilitador',
    'en': 'Hear your facilitator\'s reply',
  },
  'leaveAQuestion': {
    'pt': 'Deixar uma pergunta para o facilitador',
    'en': 'Leave a question for your facilitator',
  },
};

String handLabelFor(String state, String language) =>
    handLabels[state]![language] ?? handLabels[state]![floorLanguage]!;

const roomLabels = {
  'hearAgain': {'pt': 'Ouvir de novo', 'en': 'Hear that again'},
  'leavePassage': {
    'pt': 'Escolher outra passagem',
    'en': 'Choose another passage',
  },
  'backToPassage': {
    'pt': 'Voltar para a passagem atual',
    'en': 'Back to the current passage',
  },
  'backToRecording': {
    'pt': 'Voltar para a gravação',
    'en': 'Back to recording',
  },
  'beginAgain': {'pt': 'Começar de novo', 'en': 'Begin again'},
  'recordEnsaio': {
    'pt': 'Gravar o ensaio de vocês',
    'en': 'Record your rehearsal',
  },
  'openEnsaioFinal': {
    'pt': 'Abrir o Ensaio Final',
    'en': 'Open the Final Rehearsal',
  },
  'hearHowYouToldPart': {
    'pt': 'Ouvir como vocês contaram a parte {n}',
    'en': 'Hear how you told part {n}',
  },
};

String roomLabelFor(String control, String language, {int? n}) =>
    (roomLabels[control]![language] ?? roomLabels[control]![floorLanguage]!)
        .replaceAll('{n}', '$n');

/// Her Ensaio Final plan's words (strings.ts), the ones the team reads.
const ensaioFinalPlanLabels = {
  'title': {'pt': 'Ensaio Final', 'en': 'Final Rehearsal'},
  'sub': {
    'pt': 'Estes são os ensaios das cenas que vocês me enviaram.',
    'en': 'These are the scene rehearsals you sent me.',
  },
  'thinking': {'pt': 'pensando…', 'en': 'thinking…'},
  'sceneByScene': {
    'pt': 'Gravar cena por cena',
    'en': 'Record scene by scene instead',
  },
  'row': {
    'pt': 'ensaio {n} · {clock} · {dur} · {k} frases',
    'en': 'rehearsal {n} · {clock} · {dur} · {k} sentences',
  },
  'partial': {'pt': 'tradução incompleta', 'en': 'translation incomplete'},
  'swap': {
    'pt': 'trocar o ensaio desta cena',
    'en': 'use another rehearsal for this scene',
  },
  'missing': {
    'pt': 'falta o ensaio desta cena',
    'en': 'this scene has no rehearsal yet',
  },
  'cannotEnter': {
    'pt': 'este ensaio não pode entrar — ensaiem esta cena de novo',
    'en': 'this rehearsal cannot be used — rehearse this scene again',
  },
  'join': {'pt': 'juntar as cenas e ouvir', 'en': 'join the scenes and listen'},
  'listen': {'pt': 'Ouvir', 'en': 'Listen'},
  'joining': {
    'pt': 'juntando a cena {i} de {k}…',
    'en': 'joining scene {i} of {k}…',
  },
  'joinRetry': {
    'pt': 'não deu para juntar esta cena — toquem para tentar de novo',
    'en': 'this scene could not be joined — tap to try again',
  },
  'back': {'pt': 'Voltar para a gravação', 'en': 'Back to recording'},
  'useThis': {'pt': 'usar este', 'en': 'use this one'},
  'inUse': {'pt': 'em uso', 'en': 'in use'},
  'recordSceneAgain': {
    'pt': 'gravar esta cena de novo',
    'en': 'record this scene again',
  },
  'whichScene': {
    'pt': 'De que cena é este ensaio?',
    'en': 'Which scene is this rehearsal?',
  },
  'labelFailed': {
    'pt': 'não deu para guardar a resposta — toquem de novo',
    'en': 'couldn\'t keep that answer — tap again',
  },
  'useScene': {
    'pt': 'usar o ensaio desta cena',
    'en': 'use this scene\'s rehearsal',
  },
  'hearNewScene': {
    'pt': 'ouçam a cena nova antes de conferir',
    'en': 'listen to the new scene before the check',
  },
};

String ensaioFinalPlanLabelFor(
  String control,
  String language, {
  int? i,
  int? k,
}) {
  final label =
      ensaioFinalPlanLabels[control]![language] ??
      ensaioFinalPlanLabels[control]![floorLanguage]!;
  return i == null || k == null
      ? label
      : label.replaceAll('{i}', '$i').replaceAll('{k}', '$k');
}

/// A local time as the room writes it, `HH:MM`.
String clockOf(DateTime at) {
  final local = at.toLocal();
  return '${'${local.hour}'.padLeft(2, '0')}:'
      '${'${local.minute}'.padLeft(2, '0')}';
}

/// A length as the room writes it, `m:ss`, in whole seconds cut down.
String minutesAndSecondsOf(Duration length) =>
    '${length.inMinutes}:${'${length.inSeconds % 60}'.padLeft(2, '0')}';

/// The First listen's place: «parte 2 · 0:41 / 1:10», the part's own clock.
String firstListenPositionFor(
  int part,
  Duration at,
  Duration? length,
  String language,
) {
  final ofThePart = length != null && length > Duration.zero
      ? ' / ${minutesAndSecondsOf(length)}'
      : '';
  return '${retroLabelFor('part', language)} $part · '
      '${minutesAndSecondsOf(at)}$ofThePart';
}

/// A plan row's facts, her `rowText`: its number, its local clock, its length `m:ss`
/// rounded to the nearest second as her `fmtDur` does, and its current frases.
String planRowFactsFor(SceneRehearsalRecord rehearsal, String language) {
  final at = rehearsal.recordedAt;
  final seconds = ((rehearsal.durationMs ?? 0) / 1000).round();
  return ensaioFinalPlanLabelFor('row', language)
      .replaceAll('{n}', '${rehearsal.n}')
      .replaceAll('{clock}', at == null ? '' : clockOf(at))
      .replaceAll('{dur}', minutesAndSecondsOf(Duration(seconds: seconds)))
      .replaceAll('{k}', '${rehearsal.translatedFrases}');
}

/// A line of the Rehearsal sheet, her `candidateLine`: the row's facts, whether the voice
/// received it, and «tradução incompleta» when a stretch is left untranslated.
String sheetLineFor(SceneRehearsalRecord rehearsal, String language) => [
  planRowFactsFor(rehearsal, language),
  sceneRehearsalLabelFor(
    rehearsal.unsent ? 'listUnsent' : 'listSent',
    language,
  ),
  if (rehearsal.untranslatedStretch)
    ensaioFinalPlanLabelFor('partial', language),
].join(' · ');

/// Her scene-rehearsal words (strings.ts).
const sceneRehearsalLabels = {
  'enter': {'pt': 'ensaio da cena', 'en': 'scene rehearsal'},
  'record': {
    'pt': 'Gravar o ensaio da cena',
    'en': 'Record the scene rehearsal',
  },
  'recording': {
    'pt': 'gravem o ensaio da cena na língua materna; toquem para parar',
    'en': 'record the scene rehearsal in your own language; tap to stop',
  },
  'translate': {
    'pt': 'traduzir o ensaio da cena',
    'en': 'translate the scene rehearsal',
  },
  'again': {
    'pt': 'gravar o ensaio da cena de novo',
    'en': 'record the scene rehearsal again',
  },
  'send': {'pt': 'terminei', 'en': 'done'},
  'restart': {'pt': 'recomeçar a tradução', 'en': 'start the translation over'},
  'placesUnknown': {
    'pt':
        'as frases já traduzidas não estão neste computador — toquem em terminei para enviar, ou recomecem a tradução',
    'en':
        'the phrases already translated are not on this computer — tap done to send them, or start the translation over',
  },
  'sending': {
    'pt': 'enviando a tradução do ensaio da cena para a voz…',
    'en': 'sending the translation of the scene rehearsal to the voice…',
  },
  'listen': {
    'pt':
        'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de vocês.',
    'en':
        'This scene rehearsal\'s translation already went to the voice. Tap a phrase to hear the rehearsal there, and the speaker to hear your translation of it.',
  },
  'saving': {
    'pt': 'guardando o ensaio da cena…',
    'en': 'keeping the scene rehearsal…',
  },
  'saveFailed': {
    'pt': 'não deu para guardar o ensaio da cena — gravem de novo',
    'en': 'couldn\'t keep the scene rehearsal — record it again',
  },
  'diskFailed': {
    'pt': 'não deu para guardar o ensaio da cena neste computador',
    'en': 'couldn\'t keep the scene rehearsal on this computer',
  },
  'notSent': {
    'pt': 'não deu para enviar agora — tentem de novo',
    'en': 'couldn\'t send it now — try again',
  },
  'alreadySent': {
    'pt': 'a tradução deste ensaio da cena já foi para a voz',
    'en': 'this scene rehearsal\'s translation already went to the voice',
  },
  'tooLarge': {
    'pt': 'grande demais para o servidor — grave em partes menores',
    'en': 'too large for the server — record in shorter parts',
  },
  'retry': {
    'pt': 'falhou — toque para tentar de novo',
    'en': 'failed — tap to try again',
  },
  'lost': {'pt': 'falhou', 'en': 'failed'},
  'refused': {
    'pt': 'não foi aceita — grave de novo',
    'en': 'not accepted — record it again',
  },
  'takeRecording': {'pt': 'gravando', 'en': 'recording'},
  'stopSending': {'pt': 'parar', 'en': 'stop'},
  'stopSendingAria': {
    'pt': 'Parar o envio (a gravação fica neste computador)',
    'en': 'Stop sending (the recording stays on this computer)',
  },
  'playPause': {
    'pt': 'Tocar ou pausar a gravação',
    'en': 'Play or pause your recording',
  },
  'frase': {'pt': 'frase {n}', 'en': 'phrase {n}'},
  'hearMine': {
    'pt': 'ouvir a minha tradução da frase {n}',
    'en': 'hear my translation of sentence {n}',
  },
  'rerecordFrase': {
    'pt': 'regravar a frase {n}',
    'en': 're-record sentence {n}',
  },
  'retellFrase': {
    'pt': 'Ouvir esta frase de novo e traduzir de novo — {n}',
    'en': 'Hear this sentence again and translate it again — {n}',
  },
  'retelling': {
    'pt': 'traduzindo de novo a frase {n} — toquem no círculo',
    'en': 'translating sentence {n} again — tap the circle',
  },
  'retellingLast': {
    'pt':
        'traduzindo de novo a frase {n} — se precisar, movam a pausa; depois toquem no círculo',
    'en':
        'translating sentence {n} again — move the pause if you need to; then tap the circle',
  },
  'retellingOther': {
    'pt':
        'traduzindo de novo a frase {n} — toquem no círculo (a pausa só se move na última frase; para mudar uma pausa anterior, recomeçar a tradução)',
    'en':
        'translating sentence {n} again — tap the circle (the pause only moves on the last sentence; to change an earlier pause, start the translation over)',
  },
  'keepTheEarlier': {
    'pt': 'manter a tradução de antes',
    'en': 'keep the earlier translation',
  },
  'respeakHint': {
    'pt': 'gravem a frase inteira',
    'en': 'record the whole sentence',
  },
  'listenN': {'pt': 'Ouvir — {n}', 'en': 'Listen — {n}'},
  'recordAgain': {'pt': 'gravar de novo', 'en': 'record again'},
  'useTake': {'pt': 'usar esta', 'en': 'use this one'},
  'takeSending': {'pt': 'enviando…', 'en': 'sending…'},
  'awaiting': {
    'pt': 'regravada — traduzam esta frase',
    'en': 're-recorded — translate this sentence',
  },
  'spliceFail': {
    'pt': 'não deu para guardar a frase — tentar de novo',
    'en': 'the sentence could not be saved — try again',
  },
  'spliceTooLong': {
    'pt': 'frase longa demais — regravem a cena',
    'en': 'sentence too long — re-record the scene',
  },
  'list': {
    'pt': 'ensaios da cena desta sessão',
    'en': 'scene rehearsals of this session',
  },
  'title': {'pt': 'Ensaio da cena', 'en': 'Scene rehearsal'},
  'resume': {
    'pt': 'continuar o ensaio da cena {n}',
    'en': 'continue scene rehearsal {n}',
  },
  'listenTo': {
    'pt': 'ouvir o ensaio da cena {n}',
    'en': 'listen to scene rehearsal {n}',
  },
  'sceneN': {'pt': 'cena {n}', 'en': 'scene {n}'},
  'whichScene': {
    'pt': 'Qual cena vocês vão ensaiar?',
    'en': 'Which scene are you going to rehearse?',
  },
  'frases': {'pt': 'frases traduzidas', 'en': 'translated sentences'},
  'listSent': {'pt': 'enviado', 'en': 'sent'},
  'listUnsent': {'pt': 'não enviado', 'en': 'not sent'},
  'subRecord': {
    'pt':
        'Toquem no círculo para gravar o ensaio da cena; toquem de novo para parar.',
    'en': 'Tap the circle to record the scene rehearsal; tap again to stop.',
  },
  'subTranslate': {
    'pt':
        'Ouçam o ensaio da cena; toquem no círculo para pausar onde a frase acaba, e de novo para traduzir só aquela frase.',
    'en':
        'Listen to the scene rehearsal; tap the circle to pause where the phrase ends, and again to translate only that phrase.',
  },
  'tell': {
    'pt': 'Toque para traduzir esta frase do ensaio da cena',
    'en': 'Tap to translate this phrase of the scene rehearsal',
  },
  'listening': {
    'pt': 'ouvindo o ensaio da cena…',
    'en': 'listening to the scene rehearsal…',
  },
  'paused': {
    'pt': 'pausado — toque no círculo para marcar onde a frase acaba',
    'en': 'paused — tap the circle to mark where the sentence ends',
  },
  'ended': {'pt': 'fim do ensaio da cena', 'en': 'end of the scene rehearsal'},
  'wentToTheVoice': {
    'pt': 'a tradução do ensaio da cena foi para a voz',
    'en': 'the translation of the scene rehearsal went to the voice',
  },
  'restarted': {
    'pt': 'tradução recomeçada — o ensaio da cena ficou',
    'en': 'translation started over — the scene rehearsal stays',
  },
};

String sceneRehearsalLabelFor(String control, String language, {int? n}) =>
    (sceneRehearsalLabels[control]![language] ??
            sceneRehearsalLabels[control]![floorLanguage]!)
        .replaceAll('{n}', '$n');

/// «ouvindo o ensaio da cena…» with her clock, «0:03 / 0:20».
String sceneListeningLineFor(Duration at, Duration? length, String language) =>
    _sceneClockLineFor('listening', at, length, language);

String scenePausedLineFor(Duration? at, Duration? length, String language) =>
    switch (at) {
      final at? => _sceneClockLineFor('paused', at, length, language),
      null => sceneRehearsalLabelFor('paused', language),
    };

String _sceneClockLineFor(
  String control,
  Duration at,
  Duration? length,
  String language,
) {
  final ofTheTake = length != null && length > Duration.zero
      ? ' / ${minutesAndSecondsOf(length)}'
      : '';
  return '${sceneRehearsalLabelFor(control, language)} — '
      '${minutesAndSecondsOf(at)}$ofTheTake';
}

/// A scene button's name: «cena N» and the scene's title.
String sceneButtonLabelFor(int n, String title, String language) =>
    '${sceneRehearsalLabelFor('sceneN', language, n: n)} $title';

/// The picked scene above the circle: «cena N · título».
String sceneChipTextFor(int n, String title, String language) =>
    '${sceneRehearsalLabelFor('sceneN', language, n: n)} · $title';

/// The chip's name: its text, then the question a tap on it goes back to.
String sceneChipLabelFor(int n, String title, String language) =>
    '${sceneChipTextFor(n, title, language)} — '
    '${sceneRehearsalLabelFor('whichScene', language)}';

/// What VoiceOver says of one row of the scene rehearsals' list: its name, its scene,
/// its time, its translated frases and whether it went to the voice.
String sceneRehearsalRowLabelFor(
  SceneRehearsalRecord row,
  String language, {
  required bool onScreen,
}) {
  String said(String control, [int? n]) =>
      sceneRehearsalLabelFor(control, language, n: n);
  final name = onScreen
      ? '${said('title')} ${row.n}'
      : said(row.unsent ? 'resume' : 'listenTo', row.n);
  final scene = row.sceneNumber;
  final at = row.recordedAt;
  return [
    name,
    if (scene != null) ' — ${said('sceneN', scene)}',
    if (at != null) ', ${clockOf(at)}',
    ', ${row.translatedFrases} · ${said('frases')}',
    ', ${said(row.unsent ? 'listUnsent' : 'listSent')}',
  ].join();
}

const retroLabels = {
  'record': {
    'pt': 'Tocar para gravar a tradução deste trecho',
    'en': 'Tap to record this stretch\'s translation',
  },
  'recordAgain': {
    'pt': 'Tocar para gravar a tradução de novo',
    'en': 'Tap to record the translation again',
  },
  'recording': {'pt': 'Tocar ao terminar', 'en': 'Tap when you finish'},
  'listening': {
    'pt': 'ouvindo a gravação de vocês…',
    'en': 'listening to your recording…',
  },
  'paused': {
    'pt': 'pausado — toque no círculo para marcar onde a frase acaba',
    'en': 'paused — tap the circle to mark where the sentence ends',
  },
  'endOfTheRecording': {'pt': 'fim da gravação', 'en': 'end of the recording'},
  'listen': {'pt': 'Ouvir', 'en': 'Listen'},
  'listenToTheTranslation': {
    'pt': 'Ouvir a tradução',
    'en': 'Listen to the translation',
  },
  'pause': {'pt': 'Pausar', 'en': 'Pause'},
  'pauseEarlier': {'pt': 'um pouco antes', 'en': 'a little earlier'},
  'hearThePause': {'pt': 'ouvir a pausa', 'en': 'hear the pause'},
  'pauseLater': {'pt': 'um pouco depois', 'en': 'a little later'},
  'pauseHint': {
    'pt':
        'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para traduzir',
    'en':
        'the pause is here — listen, move it if you need to, then tap the '
        'circle to translate',
  },
  'pauseAtTheTap': {
    'pt': 'a pausa ficou no toque — toquem no círculo para traduzir',
    'en': 'the pause is at your tap — tap the circle to translate',
  },
  'listenOnly': {
    'pt': 'Primeiro, só ouvir: a passagem inteira, do começo ao fim.',
    'en': 'First, just listen: the whole passage, from beginning to end.',
  },
  'listenOnlyRecording': {
    'pt': 'Primeiro, só ouvir: a gravação de vocês inteira, do começo ao fim.',
    'en': 'First, just listen: your whole recording, from beginning to end.',
  },
  'advance': {'pt': 'terminei', 'en': 'done'},
  'checking': {'pt': 'conferindo…', 'en': 'checking…'},
  'hearTheVerdict': {
    'pt': 'ouvir a resposta de novo',
    'en': 'hear the verdict again',
  },
  'checkFailed': {
    'pt': 'não deu para conferir agora — tentem de novo',
    'en': 'couldn\'t check right now — try again',
  },
  'partUnheard': {
    'pt': 'ainda falta ouvir um trecho da gravação',
    'en': 'there is still a part of the recording to listen to',
  },
  'stretchUntranslated': {
    'pt':
        "falta traduzir um trecho — ouçam e traduzam, depois toquem em 'terminei'",
    'en': "one stretch has no translation — listen, translate, then tap 'done'",
  },
  'nothingTranslated': {
    'pt': 'ainda não tem frase traduzida',
    'en': 'no sentence translated yet',
  },
  'part': {'pt': 'parte', 'en': 'part'},
  'addition': {'pt': 'acrescentado', 'en': 'added'},
  'missing': {'pt': 'faltou depois desta', 'en': 'missing after this'},
  'unclear': {'pt': 'não ficou claro', 'en': 'unclear'},
  'stale': {
    'pt': 'regravada — traduzam de novo',
    'en': 're-recorded — translate again',
  },
  'title': {'pt': 'Traduzir a gravação', 'en': 'Translate the recording'},
  'subTell': {
    'pt':
        'Toquem no círculo para pausar onde a frase acaba; toquem de novo para traduzir só o que aquela frase diz, e de novo para a gravação seguir.',
    'en':
        'Tap the circle to pause where the sentence ends; tap again to translate only what that sentence says, and again so the recording goes on.',
  },
  'subVerdict': {
    'pt':
        'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar uma parte; ou toquem em terminei para conferir de novo.',
    'en':
        'Tap a sentence to hear it and translate it again; go back to re-record a part; or tap done to check again.',
  },
  'subVerdictSentence': {
    'pt':
        "Toquem numa frase para ouvir e traduzir de novo; toquem em regravar para gravar a frase inteira de novo; depois toquem em 'terminei'.",
    'en':
        "Tap a sentence to hear it and translate it again; tap re-record to record the whole sentence again; then tap 'done'.",
  },
  'listenToTheRecording': {
    'pt': 'Ouvir a gravação',
    'en': 'Listen to the recording',
  },
  'approve': {
    'pt': 'Aprovar como rascunho final',
    'en': 'Approve as the final draft',
  },
  'approved': {
    'pt':
        'Aprovado como rascunho final da equipe (v{n}). Próximo passo: a checagem externa — o botão aqui embaixo.',
    'en':
        'Approved as the team\'s final draft (v{n}). Next step: the external check — the button below.',
  },
  'notConferida': {
    'pt': 'para aprovar, a tradução precisa estar conferida',
    'en': 'to approve, the translation has to be checked first',
  },
  'approvedDraft': {
    'pt': '✓ aprovado como rascunho final (v{n})',
    'en': '✓ approved as the final draft (v{n})',
  },
  'reopenArmed': {
    'pt': 'toquem de novo: isto abre de novo o rascunho aprovado',
    'en': 'tap again: this re-opens the approved draft',
  },
  'externalCheck': {'pt': 'Checagem externa', 'en': 'External check'},
  'listenersOne': {
    'pt': 'checagem externa: 1 ouvinte',
    'en': 'external check: 1 listener',
  },
  'listeners': {
    'pt': 'checagem externa: {n} ouvintes',
    'en': 'external check: {n} listeners',
  },
  'externalCheckNotFinal': {
    'pt': 'a checagem externa abre depois que o rascunho final é aprovado',
    'en': 'the external check opens after the final draft is approved',
  },
  'externalCheckFailed': {
    'pt': 'não deu para abrir a checagem externa — tentem de novo',
    'en': 'couldn\'t open the external check — try again',
  },
  'listenFirst': {'pt': 'Ouvir primeiro', 'en': 'Listen first'},
  'thinking': {'pt': 'Um instante', 'en': 'One moment'},
  'translated': {'pt': 'traduzida e conferida', 'en': 'translated and checked'},
  'notUnderstood': {
    'pt': 'não entendi — traduzam de novo esse pedaço',
    'en': 'I didn\'t catch that — translate that piece again',
  },
  'restart': {'pt': 'recomeçar a tradução', 'en': 'start the translation over'},
  'restartArmed': {
    'pt': 'toque de novo para apagar as {n} frases traduzidas',
    'en': 'tap again to discard the {n} translated sentences',
  },
  'restartArmedJoined': {
    'pt':
        'toquem de novo: as {n} traduções saem da tela e vocês traduzem a passagem inteira de novo',
    'en':
        'tap again: the {n} translations leave the screen and you translate the whole passage again',
  },
  'restartedJoined': {
    'pt': 'tradução recomeçada — a gravação da passagem ficou',
    'en': 'translation started over — the passage recording stays',
  },
  'restarted': {
    'pt': 'tradução recomeçada — o ensaio da passagem ficou',
    'en': 'translation started over — the passage rehearsal stays',
  },
  'pauseOnlyOnTheLast': {
    'pt':
        'a pausa só se move na última frase — as frases mudaram; toquem na barra de novo',
    'en':
        'the pause only moves on the last sentence — the sentences changed; tap the bar again',
  },
  'pausePastTheEnd': {
    'pt': 'a pausa nova passa do fim da gravação — um pouco antes',
    'en': 'the new pause is past the end of the recording — a little earlier',
  },
  'pauseCannotStandThere': {
    'pt':
        'a pausa não pode ficar aí — a frase foi atualizada; toquem na barra de novo',
    'en':
        'the pause can\'t go there — the sentence was updated; tap the bar again',
  },
  'restartFailed': {
    'pt': 'não deu para recomeçar agora — tentem de novo',
    'en': 'couldn\'t start over right now — try again',
  },
};

String retroLabelFor(String control, String language, {int? n}) =>
    (retroLabels[control]![language] ?? retroLabels[control]![floorLanguage]!)
        .replaceAll('{n}', '$n');

String untranslatedHintFor(List<int> cenas, String language) => [
  retroLabelFor('stretchUntranslated', language),
  if (cenas.isNotEmpty)
    [
      for (final cena in cenas)
        sceneRehearsalLabelFor('sceneN', language, n: cena),
    ].join(', '),
].join(' · ');

const savedScreenLabels = {
  'title': {'pt': 'Ensaio salvo', 'en': 'Rehearsal saved'},
  'done': {'pt': 'Pronto', 'en': 'Done'},
};

String savedScreenLabelFor(String key, String language) =>
    savedScreenLabels[key]![language] ??
    savedScreenLabels[key]![floorLanguage]!;

/// Her recording home's words, byte for byte from her app (`strings.ts` at 18fa7c4); the
/// playing cue VoiceOver reads is the room's own.
const recordingHomeLabels = {
  'listenAll': {'pt': 'Ouvir tudo', 'en': 'Hear it all'},
  'listenAllAria': {
    'pt': 'Ouvir a gravação inteira',
    'en': 'Hear the whole recording',
  },
  'listenAllTitle': {
    'pt': 'A gravação de vocês inteira, parte por parte.',
    'en': 'Your whole recording, part by part.',
  },
  'title': {'pt': 'Gravem o ensaio de vocês', 'en': 'Record your rehearsal'},
  'how': {
    'pt': 'Como vocês querem gravar?',
    'en': 'How would you like to record it?',
  },
  'wholePassage': {'pt': 'A passagem inteira', 'en': 'The whole passage'},
  'oneRecording': {'pt': 'uma gravação', 'en': 'one recording'},
  'sceneByScene': {'pt': 'Cena por cena', 'en': 'Scene by scene'},
  'parts': {'pt': '{n} partes', 'en': '{n} parts'},
  'wholeInstead': {
    'pt': 'Gravar a passagem inteira',
    'en': 'Record the whole passage instead',
  },
  'sceneInstead': {
    'pt': 'Gravar cena por cena',
    'en': 'Record scene by scene instead',
  },
  'wholeAtOnce': {
    'pt': 'gravar a passagem inteira de uma vez',
    'en': 'record the whole passage in one go',
  },
  'wholeArmed': {
    'pt': 'toquem de novo: as cenas e as traduções ficam guardadas',
    'en': 'tap again: the scenes and the translations are kept',
  },
  'backToJoin': {
    'pt': 'Ensaio Final: juntar os ensaios das cenas',
    'en': 'Final Rehearsal: join the scene rehearsals',
  },
  'joinedTitle': {'pt': 'Ensaio Final', 'en': 'Final Rehearsal'},
  'sub': {
    'pt': 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.',
    'en': 'Record, listen back, and record again as many times as you need.',
  },
  'scene': {'pt': 'Cena {n}', 'en': 'Scene {n}'},
  'needsAll': {
    'pt': 'gravem todas as partes primeiro',
    'en': 'record every part first',
  },
  'record': {'pt': 'Gravar', 'en': 'Record'},
  'listen': {'pt': 'Ouvir', 'en': 'Listen'},
  'recordAgain': {'pt': 'Gravar de novo', 'en': 'Record again'},
  'stop': {'pt': 'Parar', 'en': 'Stop'},
  'playing': {'pt': 'tocando', 'en': 'playing'},
  'pending': {
    'pt': 'Uma gravação ainda está neste computador e não foi enviada.',
    'en': 'A recording is still on this computer and has not been sent.',
  },
  'sendNow': {'pt': 'enviar agora', 'en': 'send it now'},
  'sendAria': {'pt': 'Enviar a gravação', 'en': 'Send the recording'},
  'failed': {
    'pt': 'falhou — toque para tentar de novo',
    'en': 'failed — tap to try again',
  },
  'retryAria': {'pt': 'Tentar enviar de novo', 'en': 'Try sending again'},
  'lost': {'pt': 'falhou — grave de novo', 'en': 'failed — record it again'},
  'recording': {'pt': 'gravando', 'en': 'recording'},
  'sending': {'pt': 'enviando…', 'en': 'sending…'},
  'saved': {'pt': 'salvo', 'en': 'saved'},
  'stopSending': {'pt': 'parar', 'en': 'stop'},
  'stopSendingAria': {
    'pt': 'Parar o envio (a gravação fica neste computador)',
    'en': 'Stop sending (the recording stays on this computer)',
  },
  'tooLarge': {
    'pt': 'grande demais para o servidor — grave em partes menores',
    'en': 'too large for the server — record in shorter parts',
  },
  'refused': {
    'pt': 'não foi aceita — grave de novo',
    'en': 'not accepted — record it again',
  },
  'bringBack': {
    'pt': 'trazer de volta as traduções do ensaio desta cena',
    'en': 'bring back this scene rehearsal\'s translations',
  },
  'bringBackArmed': {
    'pt':
        'toquem de novo: as traduções do ensaio voltam; as que vocês fizeram aqui para esta cena ficam guardadas',
    'en':
        'tap again: the rehearsal\'s translations come back; the ones you made '
        'here for this scene are kept',
  },
  'bringBackFailed': {
    'pt': 'não deu para juntar esta cena — toquem para tentar de novo',
    'en': 'this scene could not be joined — tap to try again',
  },
  'translate': {'pt': 'Traduzir a gravação', 'en': 'Translate the recording'},
  'listenAndCheck': {
    'pt': 'ouvir e conferir o Ensaio Final',
    'en': 'listen to and check the Final Rehearsal',
  },
  'elsewhere': {
    'pt':
        'Os ensaios desta passagem foram gravados com o aplicativo na outra '
        'língua. Voltem para aquela língua para abrir o Ensaio Final.',
    'en':
        'This passage\'s rehearsals were recorded with the app in the other '
        'language. Switch back to that language to open the Final Rehearsal.',
  },
};

String recordingHomeLabelFor(String key, String language, {int? n}) =>
    (recordingHomeLabels[key]![language] ??
            recordingHomeLabels[key]![floorLanguage]!)
        .replaceAll('{n}', '$n');

const findingLabels = {
  'recordThePart': {
    'pt': 'voltar e regravar uma parte',
    'en': 'go back and re-record a part',
  },
};

String findingLabelFor(String control, String language) =>
    findingLabels[control]![language] ??
    findingLabels[control]![floorLanguage]!;

const escolhaLabels = {
  'choosePassage': {'pt': 'Escolha a passagem', 'en': 'Choose the Passage'},
  'bookPanorama': {'pt': 'Panorama do Livro', 'en': 'Book Panorama'},
  'allDone': {
    'pt': 'Todas as passagens foram trabalhadas',
    'en': 'Every passage has been worked through',
  },
  'readTheWheel': {
    'pt': 'Tocar para procurar as passagens',
    'en': 'Tap to look for the passages',
  },
  'approved': {'pt': 'tem um ensaio salvo', 'en': 'has a saved rehearsal'},
  'light': {'pt': 'Claro', 'en': 'Light'},
  'dark': {'pt': 'Escuro', 'en': 'Dark'},
};

String escolhaLabelFor(String control, String language) =>
    escolhaLabels[control]![language] ??
    escolhaLabels[control]![floorLanguage]!;

const externalCheckLabels = {
  'title': {'pt': 'Checagem externa', 'en': 'External check'},
  'subIdle': {
    'pt': 'Quem não ajudou a traduzir ouve a passagem e diz o que entendeu.',
    'en':
        "Those who didn't help translate hear the passage and say what they "
        'understood.',
  },
  'newListener': {'pt': 'Novo ouvinte', 'en': 'New listener'},
  'back': {'pt': 'Voltar para a gravação', 'en': 'Back to recording'},
  'listener': {'pt': 'ouvinte {n}', 'en': 'listener {n}'},
  'subPlaying': {
    'pt': 'ouvindo a passagem inteira…',
    'en': 'listening to the whole passage…',
  },
  'subRetell': {
    'pt': 'Contem, do jeito de vocês, o que ouviram.',
    'en': 'Tell, in your own way, what you heard.',
  },
  'recordHint': {
    'pt': 'toque no círculo para falar; toque de novo para parar',
    'en': 'tap the circle to speak; tap again to stop',
  },
  'recording': {'pt': 'gravando', 'en': 'recording'},
  'hearAgain': {'pt': 'ouvir de novo', 'en': 'hear it again'},
  'retellAria': {
    'pt': 'Toque para contar o que ouviu',
    'en': 'Tap to tell what you heard',
  },
  'openFail': {
    'pt': 'não deu para abrir a checagem externa — tentem de novo',
    'en': "couldn't open the external check — try again",
  },
  'clipFail': {
    'pt': 'não deu para guardar essa gravação — gravem de novo',
    'en': "couldn't keep that recording — record it again",
  },
  'done': {'pt': 'Agradecemos sua ajuda.', 'en': 'Thank you for your help.'},
  'anotherListener': {'pt': 'Outro ouvinte', 'en': 'Another listener'},
  'finishTheCheck': {'pt': 'Terminar a checagem', 'en': 'Finish the check'},
};

String externalCheckLabelFor(String control, String language, {int? n}) =>
    (externalCheckLabels[control]![language] ??
            externalCheckLabels[control]![floorLanguage]!)
        .replaceAll('{n}', '$n');

const codigoLabels = {
  'preparing': {
    'pt': 'A sala está preparando o código deste aparelho',
    'en': 'The room is getting a code for this tablet',
  },
  'showIt': {
    'pt': 'Mostre este código ao facilitador',
    'en': 'Show this code to the facilitator',
  },
};

String codigoLabelFor(String control, String language) =>
    codigoLabels[control]![language] ?? codigoLabels[control]![floorLanguage]!;

const momentLabels = {
  MomentAt.familiarization: {
    'pt': 'Familiarização · a passagem inteira',
    'en': 'Familiarization · the whole passage',
  },
  MomentAt.internalization: {
    'pt': 'Internalização · cena {n} de {k}',
    'en': 'Internalization · scene {n} of {k}',
  },
  MomentAt.articulation: {
    'pt': 'Articulação · cena {n} de {k}',
    'en': 'Articulation · scene {n} of {k}',
  },
  MomentAt.ensaioFinal: {
    'pt': 'Ensaio Final · a passagem inteira',
    'en': 'Final Rehearsal · the whole passage',
  },
};

const momentAria = {'pt': 'Momento da sessão', 'en': 'Session moment'};

String? momentLabelFor(Moment moment, String language) {
  final numbered =
      moment.at == MomentAt.internalization ||
      moment.at == MomentAt.articulation;
  if (moment.parts < 1) return null;
  if (numbered && (moment.part < 1 || moment.part > moment.parts)) return null;
  return (momentLabels[moment.at]![language] ??
          momentLabels[moment.at]![floorLanguage]!)
      .replaceAll('{n}', '${moment.part}')
      .replaceAll('{k}', '${moment.parts}');
}

String momentAriaFor(String language) =>
    momentAria[language] ?? momentAria[floorLanguage]!;

const updateLabels = {
  'line': {
    'pt': 'Há uma versão nova do aplicativo. Toquem para atualizar.',
    'en': 'There is a new version of the app. Tap to update.',
  },
  'button': {'pt': 'Atualizar', 'en': 'Update'},
};

String updateLabelFor(String key, String language) =>
    updateLabels[key]![language] ?? updateLabels[key]![floorLanguage]!;
