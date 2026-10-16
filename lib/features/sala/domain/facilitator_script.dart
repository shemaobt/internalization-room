import 'dart:math';

import 'moment.dart';
import 'scene_rehearsal.dart';

const languages = ['pt', 'en'];

const floorLanguage = 'pt';

String offlineNoticeAsset(String language) =>
    'assets/audio/$language/sem_conexao.mp3';

String micBlockedAsset(String language) =>
    'assets/audio/$language/microfone.mp3';

String strandedTakeAsset(String language) =>
    'assets/audio/$language/gravacao_presa.mp3';

const panoramaPericope = 'OV';

const instantAckLines = ['F0', 'F1', 'F2'];

const startLine = 'P0';

const tellLine = 'P1';

/// The fourth of Marcia's process lines, read by position: start, tell, unheard,
/// approved. The approval's is the fourth, never rotated.
const approvedLine = 'P3';

/// Marcia's pick: any acknowledgement but the one said last.
int acknowledgementAfter(int last, Random random) =>
    (last + 1 + random.nextInt(instantAckLines.length - 1)) %
    instantAckLines.length;

const circleLabels = {
  'needsPerson': {
    'pt': 'Um momento para uma pessoa',
    'en': 'A moment for someone',
  },
  'noteMode': {'pt': 'Enviar a pergunta', 'en': 'Send the question'},
  'teamTalk': {
    'pt': 'Conversem entre vocês — tocar quando quiserem me contar',
    'en': 'Talk among yourselves — tap when you want to tell me',
  },
  'listening': {'pt': 'Tocar ao terminar', 'en': 'Tap when you are done'},
  'offline': {'pt': 'Tocar para tentar de novo', 'en': 'Tap to try again'},
  'default': {'pt': 'Tocar para falar', 'en': 'Tap to speak'},
};

String circleLabelFor(String state, String language) =>
    circleLabels[state]![language] ?? circleLabels[state]![floorLanguage]!;

const warningNoticeLabel = {
  'pt': 'Um aviso pede que alguém venha olhar',
  'en': 'A warning is asking someone to come watch',
};

String warningNoticeLabelFor(String language) =>
    warningNoticeLabel[language] ?? warningNoticeLabel[floorLanguage]!;

const panoramaCircleLabels = {
  'pt': 'Falar com o facilitador',
  'en': 'Talk to the facilitator',
};

String panoramaCircleLabelFor(String language) =>
    panoramaCircleLabels[language] ?? panoramaCircleLabels[floorLanguage]!;

const handLabels = {
  'answering': {
    'pt': 'O facilitador está respondendo',
    'en': 'The facilitator is answering',
  },
  'hearTheAnswer': {
    'pt': 'Ouvir a resposta do facilitador',
    'en': 'Hear the facilitator\'s answer',
  },
  'cancel': {'pt': 'Cancelar a pergunta', 'en': 'Cancel the question'},
  'sent': {
    'pt': 'Pergunta enviada, aguardando resposta',
    'en': 'Question sent, waiting for an answer',
  },
  'raise': {'pt': 'Levantar a mão', 'en': 'Raise a hand'},
};

String handLabelFor(String state, String language) =>
    handLabels[state]![language] ?? handLabels[state]![floorLanguage]!;

const roomLabels = {
  'hearAgain': {'pt': 'Ouvir de novo', 'en': 'Hear it again'},
  'leavePassage': {
    'pt': 'Escolher outra passagem',
    'en': 'Choose another passage',
  },
  'backToPassage': {
    'pt': 'Voltar para a passagem atual',
    'en': 'Back to the current passage',
  },
  'micBlocked': {
    'pt': 'A sala precisa do microfone para funcionar',
    'en': 'The room needs the microphone to work',
  },
  'beginAgain': {'pt': 'Começar de novo', 'en': 'Begin again'},
  'recordEnsaio': {
    'pt': 'Gravar o ensaio de vocês',
    'en': 'Record your rehearsal',
  },
};

String roomLabelFor(String control, String language) =>
    roomLabels[control]![language] ?? roomLabels[control]![floorLanguage]!;

const recordEntryLabel = {
  'pt': 'Terminar a conversa e ir para o ensaio',
  'en': 'Finish the conversation and go to the rehearsal',
};

String recordEntryLabelFor(String language) =>
    recordEntryLabel[language] ?? recordEntryLabel[floorLanguage]!;

/// Her scene-rehearsal words (strings.ts), read only by VoiceOver.
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
  'listen': {
    'pt':
        'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de vocês.',
    'en':
        'This scene rehearsal\'s translation already went to the voice. Tap a phrase to hear the rehearsal there, and the speaker to hear your translation of it.',
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
  'frases': {'pt': 'frases traduzidas', 'en': 'translated sentences'},
  'listSent': {'pt': 'enviado', 'en': 'sent'},
  'listUnsent': {'pt': 'não enviado', 'en': 'not sent'},
};

String sceneRehearsalLabelFor(String control, String language, {int? n}) =>
    (sceneRehearsalLabels[control]![language] ??
            sceneRehearsalLabels[control]![floorLanguage]!)
        .replaceAll('{n}', '$n');

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
  final at = row.recordedAt?.toLocal();
  return [
    name,
    if (scene != null) ' — ${said('sceneN', scene)}',
    if (at != null)
      ', ${'${at.hour}'.padLeft(2, '0')}:${'${at.minute}'.padLeft(2, '0')}',
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
  'listen': {'pt': 'Ouvir', 'en': 'Listen'},
  'listenToTheTranslation': {
    'pt': 'Ouvir a tradução',
    'en': 'Listen to the translation',
  },
  'pause': {'pt': 'Pausar', 'en': 'Pause'},
  'pauseHere': {
    'pt': 'Pausar onde a frase acaba',
    'en': 'Pause where the sentence ends',
  },
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
  'confirm': {
    'pt': 'Confirmar a tradução e seguir',
    'en': 'Confirm the translation and go on',
  },
  'advance': {'pt': 'Conferir a tradução', 'en': 'Check the translation'},
  'stretch': {'pt': 'Trecho', 'en': 'Stretch'},
  'listenToTheRecording': {
    'pt': 'Ouvir a gravação',
    'en': 'Listen to the recording',
  },
  'approve': {
    'pt': 'Aprovar como rascunho final',
    'en': 'Approve as the final draft',
  },
  'listenFirst': {'pt': 'Ouvir primeiro', 'en': 'Listen first'},
  'thinking': {'pt': 'Um instante', 'en': 'One moment'},
  'translated': {'pt': 'Traduzida', 'en': 'Translated'},
  'notUnderstood': {
    'pt': 'Não entendi — traduzam de novo esse pedaço',
    'en': 'I didn\'t catch that — translate that piece again',
  },
};

String retroLabelFor(String control, String language) =>
    retroLabels[control]![language] ?? retroLabels[control]![floorLanguage]!;

const rehearsalLabels = {
  'firstPart': {
    'pt': 'Tocar para gravar o ensaio',
    'en': 'Tap to record the rehearsal',
  },
  'nextPart': {
    'pt': 'Tocar para gravar a próxima parte',
    'en': 'Tap to record the next part',
  },
  'recording': {'pt': 'Tocar ao terminar', 'en': 'Tap when you finish'},
  'pending': {
    'pt': 'Tocar para gravar esta parte de novo',
    'en': 'Tap to record this part again',
  },
  'play': {'pt': 'Ouvir o ensaio até aqui', 'en': 'Hear the rehearsal so far'},
  'pause': {'pt': 'Pausar o ensaio', 'en': 'Pause the rehearsal'},
  'check': {'pt': 'Confirmar esta parte', 'en': 'Confirm this part'},
  'advance': {'pt': 'Ir para a tradução', 'en': 'Go to the translation'},
  'part': {'pt': 'Parte {n}', 'en': 'Part {n}'},
  'partPlaying': {'pt': 'Parte {n}, tocando', 'en': 'Part {n}, playing'},
  'partNotDelivered': {
    'pt': 'Parte {n}, ainda não enviada',
    'en': 'Part {n}, not sent yet',
  },
  'partPlayingNotDelivered': {
    'pt': 'Parte {n}, tocando, ainda não enviada',
    'en': 'Part {n}, playing, not sent yet',
  },
};

String rehearsalLabelFor(String state, String language, {int? part}) =>
    (rehearsalLabels[state]![language] ??
            rehearsalLabels[state]![floorLanguage]!)
        .replaceAll('{n}', '$part');

const findingLabels = {
  'circle': {'pt': 'Ouvir o achado de novo', 'en': 'Hear the finding again'},
  'play': {
    'pt': 'Ouvir o trecho e a tradução',
    'en': 'Hear the stretch and its translation',
  },
  'recordThePart': {
    'pt': 'Gravar a parte de novo na língua materna',
    'en': 'Record the part again in the mother tongue',
  },
  'translateTheStretch': {
    'pt': 'Traduzir este trecho de novo',
    'en': 'Translate this stretch again',
  },
  'continue': {'pt': 'Continuar o ensaio', 'en': 'Continue the rehearsal'},
};

String findingLabelFor(String control, String language) =>
    findingLabels[control]![language] ??
    findingLabels[control]![floorLanguage]!;

const escolhaLabels = {
  'allDone': {
    'pt': 'Todas as passagens foram trabalhadas',
    'en': 'Every passage has been worked through',
  },
  'readTheWheel': {
    'pt': 'Tocar para procurar as passagens',
    'en': 'Tap to look for the passages',
  },
  'hearAgain': {
    'pt': 'Ouvir esta passagem de novo',
    'en': 'Hear this passage again',
  },
  'enter': {'pt': 'Entrar nesta passagem', 'en': 'Enter this passage'},
  'ruler': {
    'pt': 'Escolher a passagem, correndo o dedo pela fileira',
    'en': 'Choose the passage by running a finger along the row',
  },
  'place': {'pt': '{n} de {total}', 'en': '{n} of {total}'},
  'current': {'pt': 'passagem atual', 'en': 'current passage'},
  'approved': {'pt': 'tem um ensaio salvo', 'en': 'has a saved rehearsal'},
  'light': {'pt': 'Claro', 'en': 'Light'},
  'dark': {'pt': 'Escuro', 'en': 'Dark'},
};

String escolhaLabelFor(String control, String language) =>
    escolhaLabels[control]![language] ??
    escolhaLabels[control]![floorLanguage]!;

String rulerPlaceFor(int place, int total, String language) => escolhaLabelFor(
  'place',
  language,
).replaceAll('{n}', '$place').replaceAll('{total}', '$total');

const panoramaEntryLabel = {'pt': 'Panorama do Livro', 'en': 'Book Panorama'};

String entrarLabelFor({required bool isPanorama, required String language}) =>
    isPanorama
    ? (panoramaEntryLabel[language] ?? panoramaEntryLabel[floorLanguage]!)
    : escolhaLabelFor('enter', language);

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
