import 'package:flutter/material.dart';

abstract class ShemaBrand {
  static const branco = Color(0xFFF6F5EB);
  static const areia = Color(0xFFC5C29F);
  static const azul = Color(0xFF89AAA3);
  static const telha = Color(0xFFBE4A01);
  static const verdeClaro = Color(0xFF777D45);
  static const verde = Color(0xFF3F3E20);
  static const preto = Color(0xFF0A0703);

  static const woodHi = Color(0xFFE2C08F);
  static const wood = Color(0xFFC9A26B);
  static const woodLo = Color(0xFF7E5F36);

  static const azulHi = Color(0xFFA6C0BA);
  static const azulLo = Color(0xFF5E7A74);
  static const azulInk = Color(0xFF3F6862);

  static const verdeHi = Color(0xFF9AA061);
  static const verdeLo = Color(0xFF4C5028);
}

@immutable
class SalaColors extends ThemeExtension<SalaColors> {
  final Color pg;
  final Color paper;
  final Color ink;
  final Color mut;
  final Color line;
  final Color card;
  final Color cord;
  final Color telha;
  final Color halo;
  final Color oatHi;
  final Color oat;
  final Color clayHi;
  final Color clay;
  final Color elev;

  const SalaColors({
    required this.pg,
    required this.paper,
    required this.ink,
    required this.mut,
    required this.line,
    required this.card,
    required this.cord,
    required this.telha,
    required this.halo,
    required this.oatHi,
    required this.oat,
    required this.clayHi,
    required this.clay,
    required this.elev,
  });

  static const light = SalaColors(
    pg: Color(0xFFEFEDE2),
    paper: Color(0xFFF6F5EB),
    ink: Color(0xFF0A0703),
    mut: Color(0xFF6D6C56),
    line: Color(0x293F3E20),
    card: Color(0xFFECEADF),
    cord: Color(0xFFC5C29F),
    telha: Color(0xFFBE4A01),
    halo: Color(0x59BE4A01),
    oatHi: Color(0xFFFBFAF3),
    oat: Color(0xFFE7E3D3),
    clayHi: Color(0xFFD9CDBB),
    clay: Color(0xFFB9A990),
    elev: Color(0xFFFFFFFF),
  );

  static const dark = SalaColors(
    pg: Color(0xFF100D08),
    paper: Color(0xFF1A150E),
    ink: Color(0xFFF2EDE1),
    mut: Color(0xFFA79E8C),
    line: Color(0x29F2EDE1),
    card: Color(0xFF241D13),
    cord: Color(0xFF4A4336),
    telha: Color(0xFFE36A1E),
    halo: Color(0x73E36A1E),
    oatHi: Color(0xFF3A332A),
    oat: Color(0xFF2C2620),
    clayHi: Color(0xFF5A5045),
    clay: Color(0xFF463E33),
    elev: Color(0xFF221B12),
  );

  static SalaColors of(BuildContext context) =>
      Theme.of(context).extension<SalaColors>()!;

  @override
  SalaColors copyWith() => this;

  @override
  SalaColors lerp(SalaColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return SalaColors(
      pg: mix(pg, other.pg),
      paper: mix(paper, other.paper),
      ink: mix(ink, other.ink),
      mut: mix(mut, other.mut),
      line: mix(line, other.line),
      card: mix(card, other.card),
      cord: mix(cord, other.cord),
      telha: mix(telha, other.telha),
      halo: mix(halo, other.halo),
      oatHi: mix(oatHi, other.oatHi),
      oat: mix(oat, other.oat),
      clayHi: mix(clayHi, other.clayHi),
      clay: mix(clay, other.clay),
      elev: mix(elev, other.elev),
    );
  }
}
