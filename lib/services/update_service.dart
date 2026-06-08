import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// Info rilis terbaru dari GitHub Releases.
class UpdateInfo {
  final String version; // versi bersih, mis. "1.2.0"
  final String tagName; // tag asli, mis. "v1.2.0"
  final String releaseNotes; // body markdown rilis
  final String htmlUrl; // halaman rilis di GitHub
  final String? installerUrl; // browser_download_url aset installer (.exe)
  final String? installerName;
  final int? installerSize;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.htmlUrl,
    this.installerUrl,
    this.installerName,
    this.installerSize,
  });

  bool get hasInstaller => installerUrl != null;
}

/// Dilempar saat proses cek/unduh pembaruan gagal.
class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

/// Pengecek pembaruan via GitHub Releases (repo publik, tanpa token).
///
/// PENTING: ganti [_owner] & [_repo] sesuai repo GitHub kamu, lalu pastikan
/// kamu meng-upload installer (.exe dari Inno Setup) sebagai aset di tiap rilis.
class UpdateService {
  // ───────────────────────── KONFIGURASI ─────────────────────────
  // TODO(gxkuat): ganti dengan username & nama repo GitHub kamu.
  static const String _owner = 'fakedevbagus';
  static const String _repo = 'passman';
  // ────────────────────────────────────────────────────────────────

  static const String _userAgent = 'Passman-Updater';

  final HttpClient _client;
  UpdateService({HttpClient? client}) : _client = client ?? HttpClient();

  Uri get _latestUri =>
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');

  Uri get releasesPageUri =>
      Uri.parse('https://github.com/$_owner/$_repo/releases');

  /// Versi aplikasi yang sedang berjalan (dari package_info_plus).
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version; // mis. "1.0.0"
  }

  /// Cek rilis terbaru. Balikin [UpdateInfo] kalau ADA versi lebih baru dari
  /// yang terpasang, atau null kalau sudah paling baru.
  Future<UpdateInfo?> checkForUpdate() async {
    final current = await currentVersion();
    final latest = await fetchLatest();
    if (isNewer(latest.version, current)) return latest;
    return null;
  }

  /// Ambil metadata rilis terbaru (tanpa membandingkan versi).
  Future<UpdateInfo> fetchLatest() async {
    final HttpClientResponse resp;
    try {
      final req = await _client.getUrl(_latestUri);
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      resp = await req.close();
    } catch (e) {
      throw UpdateException('Gagal menghubungi GitHub: $e');
    }
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode == 404) {
      throw UpdateException('Belum ada rilis di repo ini.');
    }
    if (resp.statusCode == 403) {
      throw UpdateException('Rate limit GitHub tercapai. Coba lagi nanti.');
    }
    if (resp.statusCode != 200) {
      throw UpdateException('GitHub merespons kode ${resp.statusCode}.');
    }
    final dynamic json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw UpdateException('Format respons GitHub tidak dikenali.');
    }
    final tag = (json['tag_name'] ?? '').toString();
    if (tag.isEmpty) throw UpdateException('Rilis tanpa tag versi.');

    String? installerUrl;
    String? installerName;
    int? installerSize;
    final assets = json['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] ?? '').toString();
        final lower = name.toLowerCase();
        if (!lower.endsWith('.exe')) continue;
        final isSetup = lower.contains('setup') || lower.contains('install');
        // Ambil .exe pertama; prioritaskan yang jelas-jelas installer.
        if (installerUrl == null || isSetup) {
          installerUrl = (a['browser_download_url'] ?? '').toString();
          installerName = name;
          installerSize = (a['size'] as num?)?.toInt();
          if (isSetup) break;
        }
      }
    }

    return UpdateInfo(
      version: _clean(tag),
      tagName: tag,
      releaseNotes: (json['body'] ?? '').toString(),
      htmlUrl: (json['html_url'] ?? releasesPageUri.toString()).toString(),
      installerUrl:
          (installerUrl != null && installerUrl.isNotEmpty) ? installerUrl : null,
      installerName: installerName,
      installerSize: installerSize,
    );
  }

  /// Unduh installer ke folder temp. [onProgress] dipanggil dengan
  /// (bytesDiterima, totalBytes). Balikin file installer yang siap dijalankan.
  Future<File> downloadInstaller(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.installerUrl;
    if (url == null) {
      throw UpdateException('Rilis ini tidak punya file installer (.exe).');
    }
    final dir = Directory.systemTemp.createTempSync('passman_update_');
    final file =
        File('${dir.path}\\${info.installerName ?? 'PassmanSetup.exe'}');

    final HttpClientResponse resp;
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      resp = await req.close();
    } catch (e) {
      throw UpdateException('Gagal mengunduh installer: $e');
    }
    if (resp.statusCode != 200) {
      throw UpdateException('Gagal mengunduh installer (${resp.statusCode}).');
    }
    final total = resp.contentLength;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in resp) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) onProgress(received, total);
      }
    } finally {
      await sink.close();
    }
    return file;
  }

  /// Jalankan installer lalu keluar dari app supaya file yang sedang dipakai
  /// bisa ditimpa. [silent] = pasang tanpa wizard (butuh flag Inno '/SILENT').
  Future<void> launchInstallerAndExit(File installer,
      {bool silent = false}) async {
    await Process.start(
      installer.path,
      silent ? <String>['/SILENT'] : <String>[],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  /// Buka halaman rilis di browser default (tanpa dependency tambahan).
  Future<void> openReleasePage([String? url]) async {
    final target = url ?? releasesPageUri.toString();
    // arg pertama kosong = judul window utk perintah 'start'.
    await Process.run('cmd', ['/c', 'start', '', target], runInShell: true);
  }

  void dispose() => _client.close(force: true);

  // ───────────────────────── util versi ─────────────────────────

  /// Bersihkan tag versi: buang prefix 'v' dan build-metadata setelah '+'.
  static String _clean(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    return s;
  }

  /// True kalau [candidate] lebih baru dari [current] secara numerik
  /// (mayor.minor.patch). Pre-release suffix (mis. "-beta") diabaikan.
  static bool isNewer(String candidate, String current) {
    final a = _parts(_clean(candidate));
    final b = _parts(_clean(current));
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) {
    final core = v.split('-').first; // buang pre-release "-beta" dll
    return core
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}
