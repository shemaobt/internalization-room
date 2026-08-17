const offlineNoticeAsset = 'assets/audio/sem_conexao.mp3';

const inviteToStartAsset = 'assets/audio/toque_para_comecar.mp3';

const micBlockedAsset = 'assets/audio/microfone.mp3';

const strandedTakeAsset = 'assets/audio/gravacao_presa.mp3';

const panoramaPericope = 'OV';

String fixedLineAsset(String line) => 'assets/audio/fixed/$line.mp3';

const instantAckLines = ['F0', 'F1', 'F2', 'F3'];

const inaudibleLines = ['D0', 'D1', 'D2'];

/// The lines for a question that has to reach a person: "isso merece uma resposta de
/// verdade, e vai além do que esta passagem conta — vamos guardar para levar ao
/// facilitador de vocês". Approved and shipped with the others, and nothing anywhere
/// played them: raising the hand was confirmed by a knot on the cord and no voice, which
/// is the one thing a team that cannot read has no way to interpret.
const handoffLines = ['C0', 'C1'];

/// The line for a room that has stopped and needs a person: "vamos fazer uma pausa
/// curta aqui — pode ser um bom momento para chamar o facilitador de vocês". Approved
/// and shipped with the others; nothing was playing it, so the halted circle was silent
/// and motionless, which is what a crashed app looks like to a team that cannot read.
const needsPersonLine = 'E0';

String rotated(List<String> lines, int spoken) => lines[spoken % lines.length];

