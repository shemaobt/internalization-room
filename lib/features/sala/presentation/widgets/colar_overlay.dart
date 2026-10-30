import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'motion.dart';

const _beadSize = 9.0;
const _beadGap = 11.0;

const _restOpacity = 0.55;
const _filledOpacity = 0.92;
const _growingScale = 1.1;
const _justFilledScale = 1.2;
const _rowBottom = 0.09;
const _settle = Duration(milliseconds: 1300);

class ColarOverlay extends StatefulWidget {
  final SalaSessionState session;

  const ColarOverlay({super.key, required this.session});

  @override
  State<ColarOverlay> createState() => _ColarOverlayState();
}

class _ColarOverlayState extends State<ColarOverlay> {
  int _justFrom = 0;
  int _justTo = 0;
  Timer? _settling;

  int get _filled => widget.session.coverage.beadsFilled;

  @override
  void didUpdateWidget(ColarOverlay old) {
    super.didUpdateWidget(old);
    final before = old.session.coverage.beadsFilled;
    if (_filled > before) {
      _justFrom = before;
      _justTo = _filled;
      _settling?.cancel();
      _settling = Timer(_settle, () => setState(() => _justFrom = _justTo = 0));
    }
  }

  @override
  void dispose() {
    _settling?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final total = widget.session.coverage.beadsTotal;
          final row = total * _beadSize + (total - 1) * _beadGap;
          final left = (constraints.maxWidth - row) / 2;
          final top = constraints.maxHeight * (1 - _rowBottom) - _beadSize;

          return Stack(
            children: [
              for (var i = 0; i < total; i++)
                _bead(
                  context,
                  colors,
                  i,
                  Offset(left + i * (_beadSize + _beadGap), top),
                ),
            ],
          );
        },
      ),
    );
  }

  double _scale(int i) {
    if (i >= _justFrom && i < _justTo) return _justFilledScale;
    return i == _filled - 1 ? _growingScale : 1;
  }

  Widget _bead(BuildContext context, SalaColors colors, int i, Offset at) {
    final total = widget.session.coverage.beadsTotal;
    final lit = i < _filled;
    final still = MediaQuery.disableAnimationsOf(context);

    final bead = SizedBox(
      width: _beadSize,
      height: _beadSize,
      child: AnimatedScale(
        scale: _scale(i),
        duration: still ? Duration.zero : const Duration(milliseconds: 300),
        child: AnimatedContainer(
          duration: still ? Duration.zero : _settle,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit
                ? colors.verdeClaro.withValues(alpha: _filledOpacity)
                : colors.areia.withValues(alpha: _restOpacity),
          ),
        ),
      ),
    );

    return AnimatedPositioned(
      duration: still ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      left: at.dx,
      top: at.dy,
      child: ThreadIn(index: i, total: total, child: bead),
    );
  }
}
