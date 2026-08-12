import 'package:flutter/material.dart';

class Loop extends StatefulWidget {
  final Duration period;
  final Widget Function(BuildContext context, double t) builder;
  final bool animate;

  const Loop({
    super.key,
    required this.period,
    required this.builder,
    this.animate = true,
  });

  @override
  State<Loop> createState() => _LoopState();
}

class _LoopState extends State<Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Loop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period && _controller.isAnimating) {
      _controller.stop();
    }
    _controller.duration = widget.period;
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
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
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    if (!animate) return child;
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
