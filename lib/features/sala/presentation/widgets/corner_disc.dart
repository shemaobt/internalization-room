import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

class CornerDisc extends StatelessWidget {
  static const shadow = [
    BoxShadow(color: Color(0x260A0703), offset: Offset(0, 1), blurRadius: 3),
  ];

  final IconData glyph;

  const CornerDisc({super.key, required this.glyph});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SalaColors.of(context).elev,
        boxShadow: shadow,
      ),
      child: Center(child: Icon(glyph, size: 22, color: ShemaBrand.verdeClaro)),
    );
  }
}
