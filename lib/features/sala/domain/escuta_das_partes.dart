import 'kept_take.dart';

/// What the team heard of one part of its rehearsal, in that part's own milliseconds.
class PlayedByTake {
  final String takeId;
  final List<List<int>> playedRanges;
  final int clipDurationMs;

  const PlayedByTake({
    required this.takeId,
    required this.playedRanges,
    required this.clipDurationMs,
  });

  Map<String, Object?> toJson() => {
        'take_id': takeId,
        'played_ranges': playedRanges,
        'clip_duration_ms': clipDurationMs,
      };
}

class _Escutada {
  final List<List<int>> faixas = [];
  int? aberta;
  int medida = 0;
}

/// What the team actually heard of their own rehearsal, kept one part at a time.
///
/// This used to be invented at the very end — "nought to the length of the clip" — so the
/// report that travels to Refine said a team had listened to the whole rehearsal however
/// little of it had played, and the gate that exists to catch exactly that could never
/// fail. It is a record now: one span per stretch of listening, closed whenever the
/// rehearsal stops — with one exception, written in on purpose: the parts a telling-back
/// steps over because they were told back whole in an earlier round.
///
/// Per part, and in each part's own milliseconds, because that is how the team listens and
/// how the team re-records. Kept over the parts glued together, one retake changed the
/// length of one file and every number after it described a passage that no longer
/// existed, so the listening to every other part was thrown away with it.
///
/// The key is the part's own file, not the name the room gives it. A part exists on this
/// tablet before the room has answered for it, and the mend that rebuilds a part hands it
/// a new file and a new name in the same breath — so keying by the file is what makes a
/// mended part's listening start over by construction, with nothing to remember to clear.
/// The name is looked up when the report is drawn, and a part the room has not named yet
/// is left out of it: listening with no subject is evidence about no recording.
class EscutaDasPartes {
  final Map<String, _Escutada> _partes = {};

  /// Start listening to [arquivo] at [de], a position inside that file.
  void abrir(String arquivo, int de) {
    _do(arquivo).aberta = de;
  }

  /// Stop at [ate], a position inside the same file, and write down what ran.
  ///
  /// A close that is not after the open writes nothing: standing still is not listening.
  void fechar(String arquivo, int ate) {
    final parte = _do(arquivo);
    final de = parte.aberta;
    parte.aberta = null;
    if (de == null || ate <= de) return;
    parte.faixas.add([de, ate]);
  }

  /// How long [arquivo] turned out to be, measured as it played.
  void medida(String arquivo, int quanto) {
    _do(arquivo).medida = quanto;
  }

  /// [arquivo] was heard whole, without being played now.
  void inteira(String arquivo, int quanto) {
    final parte = _do(arquivo);
    parte.medida = quanto;
    if (quanto > 0) parte.faixas.add([0, quanto]);
  }

  void esquecer(String arquivo) => _partes.remove(arquivo);

  void esquecerTudo() => _partes.clear();

  /// The report, one entry per part the team has heard something of and the room can name.
  ///
  /// The spans are sorted and joined the way the gate joins them to read, so what the room
  /// sends is what it means: the reach of the listening, not the order the team wandered
  /// in.
  List<PlayedByTake> relato(List<KeptTake> partes) => [
        for (final parte in partes)
          if (parte.takeId case final nome?)
            if (_partes[parte.path] case final escutada?)
              if (escutada.faixas.isNotEmpty)
                PlayedByTake(
                  takeId: nome,
                  playedRanges: _unidas(escutada.faixas),
                  clipDurationMs: escutada.medida,
                ),
      ];

  _Escutada _do(String arquivo) => _partes.putIfAbsent(arquivo, _Escutada.new);

  static List<List<int>> _unidas(List<List<int>> faixas) {
    final ordenadas = [for (final faixa in faixas) [faixa[0], faixa[1]]]
      ..sort((uma, outra) => uma[0].compareTo(outra[0]));
    final unidas = <List<int>>[];
    for (final faixa in ordenadas) {
      if (unidas.isNotEmpty && faixa[0] <= unidas.last[1]) {
        if (faixa[1] > unidas.last[1]) unidas.last[1] = faixa[1];
      } else {
        unidas.add(faixa);
      }
    }
    return unidas;
  }
}
