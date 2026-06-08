import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';

/// Dilempar saat pengecekan kebocoran gagal (tidak ada internet, server
/// bermasalah, dll). Pesannya sudah ramah untuk ditampilkan ke user.
class BreachCheckException implements Exception {
  final String message;
  BreachCheckException(this.message);
  @override
  String toString() => message;
}

/// Klien "Have I Been Pwned" (Pwned Passwords) dengan model **k-anonymity**.
///
/// Cara kerjanya privat: password di-hash SHA-1 secara lokal, lalu HANYA 5
/// karakter awal hash (prefix) yang dikirim ke server. Server membalas semua
/// suffix hash yang berawalan sama beserta jumlah kebocorannya, dan pencocokan
/// terakhir dilakukan di sisi kita. Jadi password maupun hash lengkap TIDAK
/// PERNAH meninggalkan perangkat.
class BreachService {
  BreachService({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  final HttpClient _client;
  static const String _host = 'api.pwnedpasswords.com';

  /// Cache per-sesi: prefix -> body response, supaya scan massal hemat request.
  final Map<String, String> _rangeCache = {};

  /// Berapa kali [password] muncul di kebocoran data publik.
  /// 0 = tidak ditemukan (relatif aman). Melempar [BreachCheckException]
  /// kalau gagal menghubungi server.
  Future<int> pwnedCount(String password) async {
    if (password.isEmpty) return 0;

    final digest = await Sha1().hash(utf8.encode(password));
    final hex = _toHex(digest.bytes).toUpperCase();
    final prefix = hex.substring(0, 5);
    final suffix = hex.substring(5);

    final body = await _fetchRange(prefix);
    for (final line in const LineSplitter().convert(body)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toUpperCase() == suffix) {
        return int.tryParse(line.substring(idx + 1).trim()) ?? 0;
      }
    }
    return 0;
  }

  Future<String> _fetchRange(String prefix) async {
    final cached = _rangeCache[prefix];
    if (cached != null) return cached;
    try {
      final uri = Uri.https(_host, '/range/$prefix');
      final req = await _client.getUrl(uri);
      // Add-Padding menambah entri palsu acak agar ukuran respons tidak
      // membocorkan apa pun lewat analisis traffic.
      req.headers.set('Add-Padding', 'true');
      req.headers.set(HttpHeaders.userAgentHeader, 'Passman-Password-Manager');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw BreachCheckException(
            'Server HIBP membalas status ${resp.statusCode}.');
      }
      final body = await resp.transform(utf8.decoder).join();
      _rangeCache[prefix] = body;
      return body;
    } on BreachCheckException {
      rethrow;
    } on SocketException {
      throw BreachCheckException(
          'Tidak ada koneksi internet. Cek kebocoran butuh online.');
    } on HttpException catch (e) {
      throw BreachCheckException('Gagal menghubungi server HIBP: ${e.message}');
    } catch (e) {
      throw BreachCheckException('Gagal mengecek kebocoran: $e');
    }
  }

  String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Kosongkan cache respons (mis. saat vault dikunci).
  void clearCache() => _rangeCache.clear();

  void dispose() => _client.close(force: true);
}
