import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';

SalaColors _installed(ThemeData theme) => theme.extension<SalaColors>()!;

void main() {
  test(
    'in the dark the tablet\'s terracotta is her #D6612A, not a brighter one',
    () {
      expect(
        _installed(AppTheme.dark).telha,
        const Color(0xFFD6612A),
        reason:
            'cada uso do terracota no escuro vestia o laranja #E36A1E, '
            'que não é o dela',
      );
    },
  );

  test(
    'the dark halo is her terracotta at the strength it had, not the old one\'s',
    () {
      expect(
        _installed(AppTheme.dark).halo,
        const Color(0x73D6612A),
        reason:
            'o halo era o laranja antigo a 45%, e o terracota agora é outro',
      );
    },
  );
}
