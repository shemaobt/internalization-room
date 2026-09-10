import 'package:flutter/material.dart';

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

class _LoopState extends State<Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );
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
    if (widget.period != oldWidget.period && _controller.isAnimating) {
      _controller.stop();
    }
    _controller.duration = widget.period;
    _follow();
  }

  void _follow() {
    if (widget.animate && !_still) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
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
      builder: (context, _) => widget.builder(
        context,
        Curves.easeInOut.transform(_controller.value),
      ),
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
      builder: (context, _) => widget.builder(
        context,
        Curves.easeOut.transform(_controller.value),
      ),
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
