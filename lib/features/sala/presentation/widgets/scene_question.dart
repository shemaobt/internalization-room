import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_question.dart';

/// «Qual cena vocês vão ensaiar?» and one button per scene, her words written on the
/// screen (ADR 0088). Focus starts on the highlighted scene, else the first.
class SceneQuestion extends StatelessWidget {
  final List<Scene> scenes;
  final String? highlighted;
  final String language;
  final ValueChanged<String> onPick;

  const SceneQuestion({
    super.key,
    required this.scenes,
    required this.highlighted,
    required this.language,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final question = sceneRehearsalLabelFor('whichScene', language);
    final focused = highlighted ?? scenes.first.sceneId;
    return Semantics(
      container: true,
      label: question,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              question,
              style: TextStyle(color: colors.ink, fontSize: 22),
            ),
          ),
          const SizedBox(height: 24),
          for (final (i, scene) in scenes.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: FocusOnArrival(
                wanted: scene.sceneId == focused,
                child: SceneButton(
                  label: sceneButtonLabelFor(i + 1, scene.title, language),
                  number: i + 1,
                  highlighted: scene.sceneId == highlighted,
                  onTap: () => onPick(scene.sceneId),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SceneButton extends StatelessWidget {
  final String label;
  final int number;
  final bool highlighted;
  final VoidCallback onTap;

  const SceneButton({
    super.key,
    required this.label,
    required this.number,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: highlighted
                  ? colors.vermelhoMic.withValues(alpha: 0.10)
                  : null,
              border: Border.all(
                color: highlighted ? colors.vermelhoMic : colors.line,
                width: highlighted ? 2.5 : 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colors.vermelhoMic,
                  child: Text('$number', style: TextStyle(color: colors.paper)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: TextStyle(color: colors.ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «cena N · título» above the circle; a tap brings the question back.
class SceneChip extends StatelessWidget {
  final String words;
  final String label;
  final bool live;
  final VoidCallback onTap;

  const SceneChip({
    super.key,
    required this.words,
    required this.label,
    required this.live,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      container: true,
      button: true,
      enabled: live,
      label: label,
      child: GestureDetector(
        onTap: live ? onTap : null,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: live ? 1 : 0.35,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: colors.vermelhoMic, width: 1.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(words, style: TextStyle(color: colors.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Takes the focus when it first appears, if [wanted].
class FocusOnArrival extends StatefulWidget {
  final bool wanted;
  final Widget child;

  const FocusOnArrival({super.key, required this.wanted, required this.child});

  @override
  State<FocusOnArrival> createState() => _FocusOnArrivalState();
}

class _FocusOnArrivalState extends State<FocusOnArrival> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (!widget.wanted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Focus(focusNode: _focus, child: widget.child),
  );
}
