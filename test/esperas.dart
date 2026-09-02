/// The two ways this suite waits for the room to answer.
///
/// [settle] spends a fixed slice of wall clock. It is the honest wait for a claim about
/// a *deadline* — that nothing happened by the time the ceiling should have fired — and
/// it is the wrong wait for everything else: the amount of clock a busy machine needs to
/// finish an upload is not knowable in advance, and a test that guesses it reports the
/// machine's load as a verdict on the code.
///
/// [until] waits for the condition the assertion is about, so a slow machine costs the
/// suite time and never a false red.
library;

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

/// Poll [condition] every 10ms until it holds, or until [limit] runs out.
///
/// The ceiling is generous because it is only ever spent in full when the condition
/// never arrives, and that test was going to fail anyway. Three seconds of a machine with
/// no CPU to spare is not a verdict on the room, and the old five-second ceiling was
/// being spent as one. One ceiling running out still fits inside the 30s a test is given
/// by default, so the failure reads as the assertion that follows it; two in a row do
/// not, and that test dies as a timeout with nothing to read — which is the sign that
/// what is missing is not clock but a condition that never arrives.
Future<void> until(
  bool Function() condition, {
  Duration limit = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
