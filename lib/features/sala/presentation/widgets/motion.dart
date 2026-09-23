import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _breathStep = Duration(microseconds: 1000000 ~/ 30);

final _ambient = _AmbientClock();

const _away = {
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
  AppLifecycleState.detached,
};

class _AmbientClock {
  final _loops = <VoidCallback>{};
  Timer? _ticking;
  AppLifecycleListener? _lifecycle;

  void join(VoidCallback redraw) {
    _loops.add(redraw);
    _lifecycle ??= AppLifecycleListener(onStateChange: (_) => _tune());
    _tune();
  }

  void leave(VoidCallback redraw) {
    _loops.remove(redraw);
    if (_loops.isEmpty) {
      _lifecycle?.dispose();
      _lifecycle = null;
    }
    _tune();
  }

  void _tune() {
    if (_loops.isEmpty ||
        _away.contains(WidgetsBinding.instance.lifecycleState)) {
      _ticking?.cancel();
      _ticking = null;
      return;
    }
    _ticking ??= Timer.periodic(_breathStep, (_) {
      for (final redraw in [..._loops]) {
        redraw();
      }
    });
  }
}

class Loop extends StatefulWidget {
  final Duration period;
  final Widget Function(BuildContext context, double t) builder;
  final bool animate;
  final bool reducible;

  const Loop({
    super.key,
    required this.period,
    required this.builder,
    this.animate = true,
    this.reducible = true,
  });

  @override
  State<Loop> createState() => _LoopState();
}

class _LoopState extends State<Loop> {
  bool _joined = false;
  Duration? _start;
  late Duration _period = widget.period;
  bool get _still =>
      widget.reducible && MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(Loop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  void _follow() {
    final moving = widget.animate && !_still;
    if (moving == _joined) return;
    _joined = moving;
    _start = null;
    if (moving) {
      _ambient.join(_redraw);
    } else {
      _ambient.leave(_redraw);
    }
  }

  void _redraw() => setState(() {});

  @override
  void dispose() {
    if (_joined) _ambient.leave(_redraw);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_joined) return widget.builder(context, 0);
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final start = _start ??= now;
    final sweep = (now - start).inMicroseconds / _period.inMicroseconds % 2;
    if (widget.period != _period) {
      _period = widget.period;
      _start = now - _period * sweep;
    }
    return widget.builder(
      context,
      Curves.easeInOut.transform(sweep <= 1 ? sweep : 2 - sweep),
    );
  }
}

class Ripple extends StatefulWidget {
  final Duration period;
  final double phase;
  final Widget Function(BuildContext context, double t) builder;

  const Ripple({
    super.key,
    required this.period,
    required this.builder,
    this.phase = 0,
  });

  @override
  State<Ripple> createState() => _RippleState();
}

class _RippleState extends State<Ripple> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
    value: widget.phase,
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return widget.builder(context, 0);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          widget.builder(context, Curves.easeOut.transform(_controller.value)),
    );
  }
}

class Pulse extends StatelessWidget {
  final Widget child;
  final double amount;
  final Duration period;
  final bool animate;

  const Pulse({
    super.key,
    required this.child,
    this.amount = 0.12,
    this.period = const Duration(milliseconds: 1000),
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) return child;
    return Loop(
      period: period,
      builder: (context, t) =>
          Transform.scale(scale: 1 + amount * t, child: child),
    );
  }
}

class PingIn extends StatelessWidget {
  final Widget child;

  const PingIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.5, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

class FadeUp extends StatelessWidget {
  final Widget child;

  const FadeUp({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }
}

/// A bead being threaded onto the cord, in its turn.
///
/// The necklace arrives while the room is still saying what the whole passage is about,
/// and a full string of beads over an unopened passage says the work is already laid out.
/// Each bead crosses in its own slice of the same short window, left to right, so the
/// necklace reads as being strung rather than switched on. Threading runs backwards on its
/// own when [threaded] goes false again, which is what makes a repeat of the opening
/// legible without a word.
class ThreadIn extends StatelessWidget {
  final int index;
  final int total;
  final bool threaded;
  final Widget child;

  const ThreadIn({
    super.key,
    required this.index,
    required this.total,
    required this.threaded,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Opacity(opacity: threaded ? 1 : 0, child: child);
    }
    final span = total > 1 ? (index / (total - 1)).clamp(0.0, 1.0) : 0.0;
    final start = span * 0.5;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: threaded ? 1 : 0),
      duration: const Duration(milliseconds: 900),
      curve: Interval(start, start + 0.5, curve: Curves.easeOut),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: child,
    );
  }
}
