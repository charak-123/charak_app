import 'package:flutter/material.dart';

class CharakColors {
  CharakColors._();
  static const bg          = Color(0xFFFFFFFF);
  static const bgSubtle    = Color(0xFFF5F8FA);
  static const primary     = Color(0xFF376CD5);
  static const primarySoft = Color(0xFFE9EFFB);
  static const primaryDeep = Color(0xFF24478F);
  static const ink         = Color(0xFF101828);
  static const inkMuted    = Color(0xFF5B6472);
  static const border      = Color(0xFFE4E8EE);
  static const success     = Color(0xFF1FAA6D);
  static const warning     = Color(0xFFE0930B);
  static const danger      = Color(0xFFE0473E);
}

class CharakText {
  CharakText._();
  static const fontFamily = 'Inter';
  static const display = TextStyle(fontFamily: fontFamily, fontSize: 30, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.6);
  static const h1      = TextStyle(fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.33);
  static const h2      = TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.18);
  static const body    = TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w400, height: 1.55);
  static const bodyMed = TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w500, height: 1.55);
  static const caption = TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w400, height: 1.45);
  static const micro   = TextStyle(fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w500, height: 1.3, letterSpacing: 0.04);
}

class CharakRadius {
  CharakRadius._();
  static const card   = Radius.circular(20);
  static const button = Radius.circular(100);
  static const input  = Radius.circular(14);
  static const pill   = Radius.circular(100);
}

class CharakSpacing {
  CharakSpacing._();
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double base = 16;
  static const double lg   = 24;
  static const double xl   = 32;
}

class CharakShadow {
  CharakShadow._();
  static const card  = BoxShadow(color: Color(0x0F101828), blurRadius: 8,  offset: Offset(0, 2));
  static const sheet = BoxShadow(color: Color(0x1F101828), blurRadius: 24, offset: Offset(0, 8));
}

class CharakDurations {
  CharakDurations._();
  static const screenPush   = Duration(milliseconds: 280);
  static const sheetOpen    = Duration(milliseconds: 240);
  static const buttonPress  = Duration(milliseconds: 100);
  static const statusChange = Duration(milliseconds: 600);
  static const successAnim  = Duration(milliseconds: 400);
  static const newRequest   = Duration(milliseconds: 320);
}
