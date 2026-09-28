import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a widget by the label its `Semantics` node carries — the room's own
/// tests read the screen the way a screen reader would, not by widget type.
Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);
