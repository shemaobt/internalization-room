import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_snapshot.dart';

class KeptRetellingButtons extends StatelessWidget {
  final List<KeptRetelling> parts;
  final String language;
  final bool away;
  final void Function(int part) onTap;

  const KeptRetellingButtons({
    super.key,
    required this.parts,
    required this.language,
    required this.away,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: screen.height * 0.155,
      child: IgnorePointer(
        ignoring: away,
        child: AnimatedOpacity(
          opacity: away ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: screen.width * 0.56),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (var index = 0; index < parts.length; index++)
                    Semantics(
                      button: true,
                      excludeSemantics: true,
                      onTap: () => onTap(index + 1),
                      label: roomLabelFor(
                        'hearHowYouToldPart',
                        language,
                        n: index + 1,
                      ),
                      child: GestureDetector(
                        onTap: () => onTap(index + 1),
                        behavior: HitTestBehavior.opaque,
                        child: Opacity(
                          opacity: 0.75,
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: ShemaBrand.areia,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: ShemaBrand.verde,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
