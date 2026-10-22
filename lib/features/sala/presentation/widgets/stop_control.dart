import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

const stopTheSendAfter = Duration(seconds: 8);

class StopControl extends StatefulWidget {
  final DateTime since;
  final String label;
  final String aria;
  final Color color;
  final VoidCallback onStop;

  const StopControl({
    super.key,
    required this.since,
    required this.label,
    required this.aria,
    required this.color,
    required this.onStop,
  });

  @override
  State<StopControl> createState() => _StopControlState();
}

class _StopControlState extends State<StopControl> {
  late final Timer _timer;
  bool _offered = false;

  @override
  void initState() {
    super.initState();
    final left = stopTheSendAfter - clock.now().difference(widget.since);
    _offered = left <= Duration.zero;
    _timer = Timer(left, () => setState(() => _offered = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_offered) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: widget.aria,
      onTap: widget.onStop,
      excludeSemantics: true,
      child: TextButton(
        onPressed: widget.onStop,
        child: Text(
          widget.label,
          style: TextStyle(color: widget.color, fontSize: 15),
        ),
      ),
    );
  }
}
