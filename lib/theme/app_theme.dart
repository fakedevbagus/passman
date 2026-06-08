import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system Passman — nuansa enterprise: tenang, fokus, profesional,
/// tapi tetap punya karakter lewat aksen indigo khas Passman.
///
/// Dipakai di main.dart:
///   MaterialApp(
///     theme: AppTheme.light(),
///     darkTheme: AppTheme.dark(),
///     themeMode: ThemeMode.system,
///   )
class AppTheme {
  AppTheme._();

  /// Warna brand utama Passman (indigo).
  static const Color brand = Color(0xFF4F46E5);

  /// Warna aksen sekunder (highlight/aksi positif).
  static const Color accent = Color(0xFF0EA5E9);

  /// Latar gelap khas — deep slate, bukan hitam pekat (nyaman di mata).
  static const Color _darkBg = Color(0xFF0E1016);
  static const Color _darkSurface = Color(0xFF161922);

  /// Latar terang — abu sangat lembut, bukan putih menyilaukan.
  static const Color _lightBg = Color(0xFFF6F7F9);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    ).copyWith(
      surface: isDark ? _darkSurface : Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? _darkBg : _lightBg,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    // Tipografi: Inter — bersih, modern, profesional.
    final t = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = t.copyWith(
      displayLarge:
          t.displayLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displayMedium:
          t.displayMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge:
          t.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    );

    final fieldFill = isDark ? const Color(0xFF1C2030) : const Color(0xFFEFF1F5);

    return base.copyWith(
      textTheme: textTheme,

      // Input field: filled, rounded, borderless sampai fokus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),

      // Tombol: sudut membulat & padding lega.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),

      // List tile: membulat + padding rapi (siap untuk layout daftar).
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withOpacity(0.5),
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),

      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        elevation: 3,
      ),
    );
  }
}
