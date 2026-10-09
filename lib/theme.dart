import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ألوان بأسلوب Claude: خلفية دافئة، نص داكن ناعم، لمسة برتقالية-طينية.
class Pal extends ThemeExtension<Pal> {
  final Color bg;
  final Color surface;
  final Color userBubble;
  final Color border;
  final Color text;
  final Color text2;
  final Color accent;
  final Color spark;
  final Color codeBg;
  final Color codeText;
  final Color danger;

  const Pal({
    required this.bg,
    required this.surface,
    required this.userBubble,
    required this.border,
    required this.text,
    required this.text2,
    required this.accent,
    required this.spark,
    required this.codeBg,
    required this.codeText,
    required this.danger,
  });

  static const Pal light = Pal(
    bg: Color(0xFFFAF9F5),
    surface: Color(0xFFFFFFFF),
    userBubble: Color(0xFFF0EEE6),
    border: Color(0xFFE6E3D8),
    text: Color(0xFF1F1E1D),
    text2: Color(0xFF73726C),
    accent: Color(0xFFC96442),
    spark: Color(0xFFD97757),
    codeBg: Color(0xFFF3F1EA),
    codeText: Color(0xFF3D3929),
    danger: Color(0xFFB3261E),
  );

  static const Pal dark = Pal(
    bg: Color(0xFF262624),
    surface: Color(0xFF30302E),
    userBubble: Color(0xFF3A3935),
    border: Color(0xFF46443F),
    text: Color(0xFFF5F4EE),
    text2: Color(0xFFA8A59C),
    accent: Color(0xFFD97757),
    spark: Color(0xFFD97757),
    codeBg: Color(0xFF1F1E1D),
    codeText: Color(0xFFE8E6DC),
    danger: Color(0xFFF2B8B5),
  );

  @override
  Pal copyWith({
    Color? bg,
    Color? surface,
    Color? userBubble,
    Color? border,
    Color? text,
    Color? text2,
    Color? accent,
    Color? spark,
    Color? codeBg,
    Color? codeText,
    Color? danger,
  }) =>
      Pal(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        userBubble: userBubble ?? this.userBubble,
        border: border ?? this.border,
        text: text ?? this.text,
        text2: text2 ?? this.text2,
        accent: accent ?? this.accent,
        spark: spark ?? this.spark,
        codeBg: codeBg ?? this.codeBg,
        codeText: codeText ?? this.codeText,
        danger: danger ?? this.danger,
      );

  @override
  Pal lerp(ThemeExtension<Pal>? other, double t) {
    if (other is! Pal) return this;
    return Pal(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      spark: Color.lerp(spark, other.spark, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeText: Color.lerp(codeText, other.codeText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension PalContext on BuildContext {
  Pal get pal => Theme.of(this).extension<Pal>() ?? Pal.light;
}

class AppTheme {
  static ThemeData build(Brightness b) {
    final p = b == Brightness.light ? Pal.light : Pal.dark;
    final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: b)
        .copyWith(
      primary: p.accent,
      onPrimary: Colors.white,
      surface: p.surface,
      onSurface: p.text,
      error: p.danger,
    );
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
      extensions: <ThemeExtension<dynamic>>[p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: p.bg),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: border(p.border),
        enabledBorder: border(p.border),
        focusedBorder: border(p.accent, 1.5),
        labelStyle: TextStyle(color: p.text2),
        hintStyle: TextStyle(color: p.text2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.text,
        contentTextStyle: TextStyle(color: p.bg),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.text2,
        textColor: p.text,
      ),
    );
  }
}

/// أيقونة الشرارة (النجمة المشعة) المميزة
class SparkIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const SparkIcon({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SparkPainter(color ?? context.pal.spark),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final Color color;
  _SparkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09;
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n - math.pi / 2;
      final outer = r * (i.isEven ? 0.98 : 0.8);
      final inner = r * 0.16;
      canvas.drawLine(
        c + Offset(math.cos(a) * inner, math.sin(a) * inner),
        c + Offset(math.cos(a) * outer, math.sin(a) * outer),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.color != color;
}
