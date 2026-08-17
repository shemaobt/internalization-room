const offlineNoticeAsset = 'assets/audio/sem_conexao.mp3';

const inviteToStartAsset = 'assets/audio/toque_para_comecar.mp3';

const micBlockedAsset = 'assets/audio/microfone.mp3';

const strandedTakeAsset = 'assets/audio/gravacao_presa.mp3';

const panoramaPericope = 'OV';

String fixedLineAsset(String line) => 'assets/audio/fixed/$line.mp3';

const instantAckLines = ['F0', 'F1', 'F2', 'F3'];

const inaudibleLines = ['D0', 'D1', 'D2'];

/// The line for a room that has stopped and needs a person: "vamos fazer uma pausa
/// curta aqui — pode ser um bom momento para chamar o facilitador de vocês". Approved
/// and shipped with the others; nothing was playing it, so the halted circle was silent
/// and motionless, which is what a crashed app looks like to a team that cannot read.
const needsPersonLine = 'E0';

String rotated(List<String> lines, int spoken) => lines[spoken % lines.length];

