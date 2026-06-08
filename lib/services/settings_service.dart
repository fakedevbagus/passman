import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Pengaturan aplikasi (tidak berisi rahasia, jadi disimpan tanpa enkripsi).
class AppSettings {
  final int autoLockMinutes; // 0 = nonaktif
  final int clipboardClearSeconds; // 0 = jangan auto-hapus
  // Default generator password acak (karakter).
  final int genLength;
  final bool genUpper;
  final bool genDigits;
  final bool genSymbols;
  // B4: default generator passphrase (gaya diceware).
  final bool genUsePassphrase; // mode terakhir dipakai di dialog generator
  final int genPhWords;
  final String genPhSeparator;
  final bool genPhCapitalize;
  final bool genPhNumber;

  const AppSettings({
    this.autoLockMinutes = 5,
    this.clipboardClearSeconds = 20,
    this.genLength = 20,
    this.genUpper = true,
    this.genDigits = true,
    this.genSymbols = true,
    this.genUsePassphrase = false,
    this.genPhWords = 5,
    this.genPhSeparator = '-',
    this.genPhCapitalize = true,
    this.genPhNumber = true,
  });

  AppSettings copyWith({
    int? autoLockMinutes,
    int? clipboardClearSeconds,
    int? genLength,
    bool? genUpper,
    bool? genDigits,
    bool? genSymbols,
    bool? genUsePassphrase,
    int? genPhWords,
    String? genPhSeparator,
    bool? genPhCapitalize,
    bool? genPhNumber,
  }) {
    return AppSettings(
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      clipboardClearSeconds: clipboardClearSeconds ?? this.clipboardClearSeconds,
      genLength: genLength ?? this.genLength,
      genUpper: genUpper ?? this.genUpper,
      genDigits: genDigits ?? this.genDigits,
      genSymbols: genSymbols ?? this.genSymbols,
      genUsePassphrase: genUsePassphrase ?? this.genUsePassphrase,
      genPhWords: genPhWords ?? this.genPhWords,
      genPhSeparator: genPhSeparator ?? this.genPhSeparator,
      genPhCapitalize: genPhCapitalize ?? this.genPhCapitalize,
      genPhNumber: genPhNumber ?? this.genPhNumber,
    );
  }

  Map<String, dynamic> toJson() => {
        'autoLockMinutes': autoLockMinutes,
        'clipboardClearSeconds': clipboardClearSeconds,
        'genLength': genLength,
        'genUpper': genUpper,
        'genDigits': genDigits,
        'genSymbols': genSymbols,
        'genUsePassphrase': genUsePassphrase,
        'genPhWords': genPhWords,
        'genPhSeparator': genPhSeparator,
        'genPhCapitalize': genPhCapitalize,
        'genPhNumber': genPhNumber,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        autoLockMinutes: (j['autoLockMinutes'] as num?)?.toInt() ?? 5,
        clipboardClearSeconds:
            (j['clipboardClearSeconds'] as num?)?.toInt() ?? 20,
        genLength: (j['genLength'] as num?)?.toInt() ?? 20,
        genUpper: j['genUpper'] as bool? ?? true,
        genDigits: j['genDigits'] as bool? ?? true,
        genSymbols: j['genSymbols'] as bool? ?? true,
        genUsePassphrase: j['genUsePassphrase'] as bool? ?? false,
        genPhWords: (j['genPhWords'] as num?)?.toInt() ?? 5,
        genPhSeparator: j['genPhSeparator'] as String? ?? '-',
        genPhCapitalize: j['genPhCapitalize'] as bool? ?? true,
        genPhNumber: j['genPhNumber'] as bool? ?? true,
      );
}

/// Baca/tulis pengaturan ke disk (atomic write).
class SettingsService {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/passman_settings.json');
  }

  Future<AppSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const AppSettings();
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(j);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(s.toJson()), flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }
}

/// State pengaturan yang reaktif (dipakai untuk auto-lock, generator, dll).
class SettingsController extends ChangeNotifier {
  final SettingsService _service;
  AppSettings _settings;
  SettingsController(this._service, this._settings);

  static Future<SettingsController> load() async {
    final svc = SettingsService();
    final s = await svc.load();
    return SettingsController(svc, s);
  }

  AppSettings get settings => _settings;

  Future<void> update(AppSettings s) async {
    _settings = s;
    notifyListeners();
    await _service.save(s);
  }
}
