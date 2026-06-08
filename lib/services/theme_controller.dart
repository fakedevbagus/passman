import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Mengelola pilihan tema (System / Light / Dark) dan menyimpannya ke disk
/// agar tetap konsisten setelah aplikasi ditutup.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}theme.cfg');
  }

  /// Muat pilihan tema dari disk. Aman dipanggil sebelum runApp().
  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        _mode = _parse((await f.readAsString()).trim());
        notifyListeners();
      }
    } catch (_) {
      // abaikan; pakai default System.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final f = await _file();
      await f.writeAsString(_encode(mode));
    } catch (_) {
      // gagal nyimpen tidak fatal.
    }
  }

  /// Putar berurutan: System -> Light -> Dark -> System ...
  Future<void> cycle() {
    switch (_mode) {
      case ThemeMode.system:
        return setMode(ThemeMode.light);
      case ThemeMode.light:
        return setMode(ThemeMode.dark);
      case ThemeMode.dark:
        return setMode(ThemeMode.system);
    }
  }

  static ThemeMode _parse(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
