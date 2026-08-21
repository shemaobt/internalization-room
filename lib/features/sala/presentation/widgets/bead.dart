import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bead_styles.dart';

class Bead extends StatelessWidget {
  final double size;
  final double opacity;
  final Border? border;

  const Bead({super.key, required this.size, this.opacity = 1, this.border});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: BeadStyles.wood,
          boxShadow: BeadStyles.matte,
          border: border,
        ),
      ),
    );
  }
}

class KnotMark extends StatelessWidget {
  final double size;

  const KnotMark({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          gradient: BeadStyles.azul,
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    );
  }
}
