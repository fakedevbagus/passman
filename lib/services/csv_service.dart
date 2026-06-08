import 'dart:io';
import 'dart:math';
import 'package:file_selector/file_selector.dart';
import '../models/vault_entry.dart';

/// Hasil parsing CSV.
class CsvImportResult {
  final List<VaultEntry> entries;
  final int skipped;
  const CsvImportResult(this.entries, this.skipped);
}

/// Import & export kredensial dalam format CSV.
///
/// Format export Passman (header): name,url,username,password,notes,totp
/// - 4 kolom pertama kompatibel dengan Chrome/Edge.
/// - 2 kolom terakhir tambahan agar tidak ada data hilang.
///
/// Import auto-deteksi header dan mendukung Chrome/Edge, Bitwarden, dan Passman.
class CsvService {
  // ───────────────────────── EXPORT ─────────────────────────

  String buildCsv(List<VaultEntry> entries) {
    final sb = StringBuffer();
    sb.writeln('name,url,username,password,notes,totp');
    for (final e in entries) {
      sb.writeln([
        e.title,
        e.url,
        e.username,
        e.password,
        e.notes,
        e.totpSecret,
      ].map(_escape).join(','));
    }
    return sb.toString();
  }

  /// Export ke file via dialog "Save As". Mengembalikan path file,
  /// null jika dibatalkan / tidak ada data.
  Future<String?> exportToFile(List<VaultEntry> entries) async {
    if (entries.isEmpty) return null;
    final group = XTypeGroup(label: 'CSV', extensions: ['csv']);
    final location = await getSaveLocation(
      suggestedName: 'passman_export.csv',
      acceptedTypeGroups: [group],
    );
    if (location == null) return null; // dibatalkan
    final file = File(location.path);
    await file.writeAsString(buildCsv(entries), flush: true);
    return location.path;
  }

  // ───────────────────────── IMPORT ─────────────────────────

  /// Pilih file CSV lewat dialog & parse. null jika dibatalkan.
  Future<CsvImportResult?> importFromFile() async {
    final group = XTypeGroup(label: 'CSV', extensions: ['csv']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null; // dibatalkan
    final content = await file.readAsString();
    return parseCsv(content);
  }

  /// Parse string CSV menjadi daftar entry. Auto-deteksi kolom.
  CsvImportResult parseCsv(String content) {
    final rows = _parseRows(content);
    if (rows.isEmpty) return const CsvImportResult([], 0);

    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final dataRows = rows.skip(1);

    int idx(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final iName = idx(['name', 'title', 'account', 'item name']);
    final iUrl = idx(['url', 'login_uri', 'website', 'uri', 'web site']);
    final iUser = idx(['username', 'login_username', 'user', 'email', 'login_email']);
    final iPass = idx(['password', 'login_password', 'pass']);
    final iNotes = idx(['notes', 'note', 'comments', 'extra']);
    final iTotp = idx(['totp', 'login_totp', 'otpauth', 'otp', 'authenticator key (totp)']);

    String cell(List<String> row, int i) =>
        (i >= 0 && i < row.length) ? row[i].trim() : '';

    final entries = <VaultEntry>[];
    var skipped = 0;
    var counter = 0;
    for (final row in dataRows) {
      if (row.every((c) => c.trim().isEmpty)) continue; // baris kosong
      final title = cell(row, iName);
      final username = cell(row, iUser);
      final password = cell(row, iPass);
      if (title.isEmpty && username.isEmpty && password.isEmpty) {
        skipped++;
        continue; // tidak ada data berarti
      }
      entries.add(VaultEntry(
        id: _genId(counter++),
        title: title.isNotEmpty
            ? title
            : (username.isNotEmpty ? username : 'Tanpa nama'),
        username: username,
        password: password,
        url: cell(row, iUrl),
        notes: cell(row, iNotes),
        totpSecret: _cleanTotp(cell(row, iTotp)),
      ));
    }
    return CsvImportResult(entries, skipped);
  }

  // ───────────────────────── helpers ─────────────────────────

  String _genId(int seq) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rnd = Random().nextInt(0x7fffffff);
    return 'csv_${ts}_${seq}_$rnd';
  }

  /// Bitwarden kadang menyimpan TOTP sebagai otpauth:// URL. Ambil secret-nya.
  String _cleanTotp(String raw) {
    if (raw.isEmpty) return '';
    if (raw.toLowerCase().startsWith('otpauth://')) {
      final uri = Uri.tryParse(raw);
      final secret = uri?.queryParameters['secret'];
      if (secret != null && secret.isNotEmpty) return secret;
    }
    return raw;
  }

  String _escape(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Parser CSV proper: menangani field ber-quote, escaped quote (""),
  /// dan newline di dalam quote.
  List<List<String>> _parseRows(String input) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    final s = input;
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(ch);
        i++;
        continue;
      } else {
        if (ch == '"') {
          inQuotes = true;
          i++;
          continue;
        }
        if (ch == ',') {
          row.add(field.toString());
          field = StringBuffer();
          i++;
          continue;
        }
        if (ch == '\r') {
          if (i + 1 < s.length && s[i + 1] == '\n') i++;
          row.add(field.toString());
          rows.add(row);
          field = StringBuffer();
          row = <String>[];
          i++;
          continue;
        }
        if (ch == '\n') {
          row.add(field.toString());
          rows.add(row);
          field = StringBuffer();
          row = <String>[];
          i++;
          continue;
        }
        field.write(ch);
        i++;
      }
    }
    if (field.length > 0 || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
