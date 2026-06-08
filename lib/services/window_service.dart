import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class WindowBounds {
  final double width;
  final double height;
  final double? x;
  final double? y;
  const WindowBounds({required this.width, required this.height, this.x, this.y});

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
      };

  factory WindowBounds.fromJson(Map<String, dynamic> j) => WindowBounds(
        width: (j['width'] as num?)?.toDouble() ?? 1000,
        height: (j['height'] as num?)?.toDouble() ?? 700,
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
      );
}

class WindowService {
  static const _fileName = 'passman_window.json';
  static const defaultBounds = WindowBounds(width: 1000, height: 700);

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<WindowBounds> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return defaultBounds;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return defaultBounds;
      return WindowBounds.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return defaultBounds;
    }
  }

  static Future<void> save(WindowBounds b) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(b.toJson()), flush: true);
      await tmp.rename(f.path); // atomic
    } catch (_) {
      // abaikan error simpan
    }
  }
}