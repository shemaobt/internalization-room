import 'dart:async';

import 'package:flutter/material.dart';

const stopTheSendAfter = Duration(seconds: 8);

class StopTheSend extends StatefulWidget {
  final String label;
  final String aria;
  final Color color;
  final VoidCallback onStop;

  const StopTheSend({
    super.key,
    required this.label,
    required this.aria,
    required this.color,
    required this.onStop,
  });

  @override
  State<StopTheSend> createState() => _StopTheSendState();
}

class _StopTheSendState extends State<StopTheSend> {
  late final Timer _timer;
  bool _offered = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(stopTheSendAfter, () => setState(() => _offered = true));
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
