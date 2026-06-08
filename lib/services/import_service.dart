import 'dart:convert';

import '../models/vault_entry.dart';

/// B4: format export yang didukung importer.
enum ImportFormat {
  chromeCsv,
  bitwardenJson,
  bitwardenCsv,
  lastpassCsv,
  onePasswordCsv,
  keepassCsv,
  genericCsv,
}

extension ImportFormatMeta on ImportFormat {
  String get label {
    switch (this) {
      case ImportFormat.chromeCsv:
        return 'Google Chrome (CSV)';
      case ImportFormat.bitwardenJson:
        return 'Bitwarden (JSON)';
      case ImportFormat.bitwardenCsv:
        return 'Bitwarden (CSV)';
      case ImportFormat.lastpassCsv:
        return 'LastPass (CSV)';
      case ImportFormat.onePasswordCsv:
        return '1Password (CSV)';
      case ImportFormat.keepassCsv:
        return 'KeePass (CSV)';
      case ImportFormat.genericCsv:
        return 'CSV umum';
    }
  }
}

/// Dilempar saat isi file tidak bisa diparse sama sekali.
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Hasil impor: entry yang siap dimasukkan + catatan masalah per baris.
class ImportResult {
  final List<VaultEntry> entries;
  final List<String> warnings;
  final ImportFormat format;
  ImportResult({
    required this.entries,
    required this.warnings,
    required this.format,
  });
  int get count => entries.length;
}

/// Parser impor massal dari berbagai aplikasi password manager.
///
/// Murni lokal & sinkron: terima konten file (string), balikin daftar
/// [VaultEntry] yang tinggal dimasukkan lewat `VaultController.addEntries`.
/// Tidak menyentuh jaringan & tidak menyimpan apa pun ke disk.
class ImportService {
  static int _seq = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Tebak format dari nama file + isi (header CSV / bentuk JSON).
  static ImportFormat detectFormat(String content, {String? fileName}) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return ImportFormat.bitwardenJson;
    }
    final rows = _parseCsv(content);
    if (rows.isEmpty) return ImportFormat.genericCsv;
    final header = rows.first.map((h) => h.trim().toLowerCase()).toSet();
    bool has(String c) => header.contains(c);

    if (has('login_password') || has('login_username') || has('login_uri')) {
      return ImportFormat.bitwardenCsv;
    }
    if (has('grouping') && has('extra')) {
      return ImportFormat.lastpassCsv;
    }
    if (has('otpauth')) {
      return ImportFormat.onePasswordCsv;
    }
    if (has('web site') || has('login name') || has('account')) {
      return ImportFormat.keepassCsv;
    }
    if (has('name') && has('url') && has('username') && has('password')) {
      return ImportFormat.chromeCsv;
    }
    return ImportFormat.genericCsv;
  }

  /// Parse [content]. Kalau [format] null, dideteksi otomatis.
  static ImportResult parse(
    String content, {
    ImportFormat? format,
    String? fileName,
  }) {
    if (content.trim().isEmpty) {
      throw ImportException('File kosong.');
    }
    final fmt = format ?? detectFormat(content, fileName: fileName);
    switch (fmt) {
      case ImportFormat.bitwardenJson:
        return _parseBitwardenJson(content, fmt);
      case ImportFormat.bitwardenCsv:
        return _parseBitwardenCsv(content, fmt);
      case ImportFormat.lastpassCsv:
        return _parseLastpassCsv(content, fmt);
      case ImportFormat.onePasswordCsv:
        return _parseOnePasswordCsv(content, fmt);
      case ImportFormat.keepassCsv:
        return _parseKeepassCsv(content, fmt);
      case ImportFormat.chromeCsv:
      case ImportFormat.genericCsv:
        return _parseGenericCsv(content, fmt);
    }
  }

  // ──────────────────────────── CSV-based ────────────────────────────

  static ImportResult _parseGenericCsv(String content, ImportFormat fmt) {
    final table = _table(content);
    final h = table.header;
    final iTitle = h.find(['name', 'title', 'account', 'item']);
    final iUser = h.find(['username', 'user', 'login', 'login name', 'email']);
    final iPass = h.find(['password', 'pass', 'login_password']);
    final iUrl = h.find(['url', 'website', 'web site', 'uri', 'login_uri']);
    final iNotes = h.find(['notes', 'note', 'comments', 'extra']);
    final iTotp = h.find(['totp', 'otp', 'otpauth', '2fa', 'login_totp']);
    final iFolder = h.find(['folder', 'group', 'grouping', 'category']);
    final iFav = h.find(['favorite', 'fav']);

    if (iTitle < 0 && iUser < 0 && iPass < 0 && iUrl < 0) {
      throw ImportException(
          'Kolom CSV tidak dikenali. Pastikan ada header seperti name/username/password/url.');
    }

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
      final title = cell(iTitle);
      final user = cell(iUser);
      final pass = iPass >= 0 ? row[iPass] : '';
      final url = cell(iUrl);
      if (title.isEmpty && user.isEmpty && pass.isEmpty && url.isEmpty) {
        continue; // baris kosong
      }
      entries.add(VaultEntry(
        id: _newId(),
        title: title.isNotEmpty
            ? title
            : (url.isNotEmpty ? _hostOf(url) : (user.isNotEmpty ? user : 'Tanpa Judul')),
        username: user,
        password: pass,
        url: url,
        notes: cell(iNotes),
        totpSecret: _extractTotp(cell(iTotp)),
        folder: cell(iFolder),
        favorite: _truthy(cell(iFav)),
      ));
    }
    if (entries.isEmpty) {
      throw ImportException('Tidak ada baris data yang bisa diimpor.');
    }
    return ImportResult(entries: entries, warnings: warnings, format: fmt);
  }

  static ImportResult _parseLastpassCsv(String content, ImportFormat fmt) {
    // url,username,password,totp,extra,name,grouping,fav
    final table = _table(content);
    final h = table.header;
    final iUrl = h.find(['url']);
    final iUser = h.find(['username']);
    final iPass = h.find(['password']);
    final iTotp = h.find(['totp']);
    final iExtra = h.find(['extra']);
    final iName = h.find(['name']);
    final iGroup = h.find(['grouping']);
    final iFav = h.find(['fav']);

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    for (final row in table.rows) {
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
      final rawUrl = cell(iUrl);
      final name = cell(iName);
      final user = cell(iUser);
      final pass = iPass >= 0 && iPass < row.length ? row[iPass] : '';
      final notes = cell(iExtra);
      // LastPass secure note ditandai url == 'http://sn'.
      final isNote = rawUrl.toLowerCase() == 'http://sn';
      if (name.isEmpty && user.isEmpty && pass.isEmpty && notes.isEmpty) {
        continue;
      }
      entries.add(VaultEntry(
        id: _newId(),
        title: name.isNotEmpty ? name : (user.isNotEmpty ? user : 'Tanpa Judul'),
        username: user,
        password: pass,
        url: isNote ? '' : rawUrl,
        notes: notes,
        totpSecret: _extractTotp(cell(iTotp)),
        folder: cell(iGroup),
        favorite: _truthy(cell(iFav)),
        type: isNote ? EntryType.secureNote : EntryType.login,
      ));
    }
    if (entries.isEmpty) {
      throw ImportException('Tidak ada baris LastPass yang bisa diimpor.');
    }
    return ImportResult(entries: entries, warnings: warnings, format: fmt);
  }

  static ImportResult _parseOnePasswordCsv(String content, ImportFormat fmt) {
    // Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes
    final table = _table(content);
    final h = table.header;
    final iTitle = h.find(['title']);
    final iUrl = h.find(['url']);
    final iUser = h.find(['username']);
    final iPass = h.find(['password']);
    final iOtp = h.find(['otpauth']);
    final iFav = h.find(['favorite']);
    final iTags = h.find(['tags']);
    final iNotes = h.find(['notes']);

    final entries = <VaultEntry>[];
    for (final row in table.rows) {
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
      final title = cell(iTitle);
      final user = cell(iUser);
      final pass = iPass >= 0 && iPass < row.length ? row[iPass] : '';
      if (title.isEmpty && user.isEmpty && pass.isEmpty) continue;
      final tags = _splitTags(cell(iTags));
      entries.add(VaultEntry(
        id: _newId(),
        title: title.isNotEmpty ? title : (user.isNotEmpty ? user : 'Tanpa Judul'),
        username: user,
        password: pass,
        url: cell(iUrl),
        notes: cell(iNotes),
        totpSecret: _extractTotp(cell(iOtp)),
        tags: tags,
        favorite: _truthy(cell(iFav)),
      ));
    }
    if (entries.isEmpty) {
      throw ImportException('Tidak ada baris 1Password yang bisa diimpor.');
    }
    return ImportResult(entries: entries, warnings: const [], format: fmt);
  }

  static ImportResult _parseKeepassCsv(String content, ImportFormat fmt) {
    // "Account","Login Name","Password","Web Site","Comments"
    final table = _table(content);
    final h = table.header;
    final iTitle = h.find(['account', 'title', 'name']);
    final iUser = h.find(['login name', 'username', 'user name']);
    final iPass = h.find(['password']);
    final iUrl = h.find(['web site', 'url']);
    final iNotes = h.find(['comments', 'notes']);

    final entries = <VaultEntry>[];
    for (final row in table.rows) {
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
      final title = cell(iTitle);
      final user = cell(iUser);
      final pass = iPass >= 0 && iPass < row.length ? row[iPass] : '';
      if (title.isEmpty && user.isEmpty && pass.isEmpty) continue;
      entries.add(VaultEntry(
        id: _newId(),
        title: title.isNotEmpty ? title : (user.isNotEmpty ? user : 'Tanpa Judul'),
        username: user,
        password: pass,
        url: cell(iUrl),
        notes: cell(iNotes),
      ));
    }
    if (entries.isEmpty) {
      throw ImportException('Tidak ada baris KeePass yang bisa diimpor.');
    }
    return ImportResult(entries: entries, warnings: const [], format: fmt);
  }

  static ImportResult _parseBitwardenCsv(String content, ImportFormat fmt) {
    // folder,favorite,type,name,notes,fields,reprompt,
    // login_uri,login_username,login_password,login_totp
    final table = _table(content);
    final h = table.header;
    final iFolder = h.find(['folder']);
    final iFav = h.find(['favorite']);
    final iType = h.find(['type']);
    final iName = h.find(['name']);
    final iNotes = h.find(['notes']);
    final iFields = h.find(['fields']);
    final iUri = h.find(['login_uri']);
    final iUser = h.find(['login_username']);
    final iPass = h.find(['login_password']);
    final iTotp = h.find(['login_totp']);

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    for (final row in table.rows) {
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
      final name = cell(iName);
      final user = cell(iUser);
      final pass = iPass >= 0 && iPass < row.length ? row[iPass] : '';
      final notes = cell(iNotes);
      if (name.isEmpty && user.isEmpty && pass.isEmpty && notes.isEmpty) {
        continue;
      }
      final typeStr = cell(iType).toLowerCase();
      final custom = _parseBitwardenCsvFields(cell(iFields));
      entries.add(VaultEntry(
        id: _newId(),
        title: name.isNotEmpty ? name : (user.isNotEmpty ? user : 'Tanpa Judul'),
        username: user,
        password: pass,
        url: cell(iUri),
        notes: notes,
        totpSecret: _extractTotp(cell(iTotp)),
        folder: cell(iFolder),
        favorite: _truthy(cell(iFav)),
        type: typeStr == 'note' ? EntryType.secureNote : EntryType.login,
        customFields: custom,
      ));
    }
    if (entries.isEmpty) {
      throw ImportException('Tidak ada baris Bitwarden yang bisa diimpor.');
    }
    return ImportResult(entries: entries, warnings: warnings, format: fmt);
  }

  // ──────────────────────────── JSON-based ────────────────────────────

  static ImportResult _parseBitwardenJson(String content, ImportFormat fmt) {
    late final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw ImportException('File JSON tidak valid.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ImportException('Struktur JSON tidak dikenali (bukan export Bitwarden).');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw ImportException('JSON tidak memuat daftar "items".');
    }

    // Map folderId -> nama folder.
    final folderNames = <String, String>{};
    final folders = decoded['folders'];
    if (folders is List) {
      for (final f in folders) {
        if (f is Map && f['id'] != null) {
          folderNames[f['id'].toString()] = (f['name'] ?? '').toString();
        }
      }
    }

    final entries = <VaultEntry>[];
    final warnings = <String>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final name = (item['name'] ?? '').toString();
      final notes = (item['notes'] ?? '').toString();
      final favorite = item['favorite'] == true;
      final folder = folderNames[item['folderId']?.toString()] ?? '';
      final type = _bwType(item['type']);
      final custom = _bitwardenJsonFields(item['fields']);

      var username = '';
      var password = '';
      var url = '';
      var totp = '';

      if (type == EntryType.login && item['login'] is Map) {
        final login = Map<String, dynamic>.from(item['login'] as Map);
        username = (login['username'] ?? '').toString();
        password = (login['password'] ?? '').toString();
        totp = _extractTotp((login['totp'] ?? '').toString());
        final uris = login['uris'];
        if (uris is List && uris.isNotEmpty && uris.first is Map) {
          url = ((uris.first as Map)['uri'] ?? '').toString();
        }
      } else if (type == EntryType.card && item['card'] is Map) {
        custom.addAll(_bitwardenCard(Map<String, dynamic>.from(item['card'] as Map)));
      } else if (type == EntryType.identity && item['identity'] is Map) {
        custom.addAll(_bitwardenIdentity(
            Map<String, dynamic>.from(item['identity'] as Map)));
      }

      if (name.isEmpty && username.isEmpty && password.isEmpty &&
          notes.isEmpty && custom.isEmpty) {
        continue;
      }
      entries.add(VaultEntry(
        id: _newId(),
        title: name.isNotEmpty ? name : (username.isNotEmpty ? username : 'Tanpa Judul'),
        username: username,
        password: password,
        url: url,
        notes: notes,
        totpSecret: totp,
        folder: folder,
        favorite: favorite,
        type: type,
        customFields: custom,
      ));
    }
    if (entries.isEmpty) {
      throw ImportException('Tidak ada item Bitwarden yang bisa diimpor.');
    }
    return ImportResult(entries: entries, warnings: warnings, format: fmt);
  }

  static EntryType _bwType(dynamic t) {
    switch (t is int ? t : int.tryParse('$t') ?? 1) {
      case 2:
        return EntryType.secureNote;
      case 3:
        return EntryType.card;
      case 4:
        return EntryType.identity;
      default:
        return EntryType.login;
    }
  }

  static List<CustomField> _bitwardenJsonFields(dynamic fields) {
    final out = <CustomField>[];
    if (fields is List) {
      for (final f in fields) {
        if (f is Map) {
          final label = (f['name'] ?? '').toString();
          final value = (f['value'] ?? '').toString();
          if (label.isEmpty && value.isEmpty) continue;
          // type 1 = hidden (rahasia)
          final secret = (f['type'] is int ? f['type'] : int.tryParse('${f['type']}')) == 1;
          out.add(CustomField(
              label: label.isEmpty ? 'Field' : label, value: value, secret: secret));
        }
      }
    }
    return out;
  }

  static List<CustomField> _bitwardenCard(Map<String, dynamic> c) {
    String s(String k) => (c[k] ?? '').toString();
    final exp = [s('expMonth'), s('expYear')].where((e) => e.isNotEmpty).join('/');
    final out = <CustomField>[];
    void add(String label, String value, {bool secret = false}) {
      if (value.trim().isEmpty) return;
      out.add(CustomField(label: label, value: value, secret: secret));
    }
    add('Nama di Kartu', s('cardholderName'));
    add('Jenis Kartu', s('brand'));
    add('Nomor Kartu', s('number'), secret: true);
    add('Berlaku Hingga (MM/YY)', exp);
    add('CVV', s('code'), secret: true);
    return out;
  }

  static List<CustomField> _bitwardenIdentity(Map<String, dynamic> c) {
    final out = <CustomField>[];
    void add(String label, String key, {bool secret = false}) {
      final v = (c[key] ?? '').toString();
      if (v.trim().isEmpty) return;
      out.add(CustomField(label: label, value: v, secret: secret));
    }
    final fullName = [c['firstName'], c['middleName'], c['lastName']]
        .map((e) => (e ?? '').toString())
        .where((e) => e.isNotEmpty)
        .join(' ');
    if (fullName.isNotEmpty) {
      out.add(CustomField(label: 'Nama Lengkap', value: fullName));
    }
    add('Email', 'email');
    add('Telepon', 'phone');
    add('No. Identitas', 'ssn', secret: true);
    add('No. Paspor', 'passportNumber', secret: true);
    add('No. SIM', 'licenseNumber', secret: true);
    add('Alamat', 'address1');
    add('Kota', 'city');
    add('Negara', 'country');
    return out;
  }

  // ──────────────────────────── helpers ────────────────────────────

  static List<CustomField> _parseBitwardenCsvFields(String raw) {
    // Bitwarden CSV menaruh custom field sebagai "label: value" per baris.
    final out = <CustomField>[];
    if (raw.trim().isEmpty) return out;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final idx = t.indexOf(':');
      if (idx <= 0) {
        out.add(CustomField(label: 'Field', value: t));
      } else {
        out.add(CustomField(
            label: t.substring(0, idx).trim(),
            value: t.substring(idx + 1).trim()));
      }
    }
    return out;
  }

  static String _extractTotp(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.toLowerCase().startsWith('otpauth://')) {
      try {
        final uri = Uri.parse(v);
        final secret = uri.queryParameters['secret'];
        if (secret != null && secret.trim().isNotEmpty) return secret.trim();
      } catch (_) {}
      return '';
    }
    return v;
  }

  static List<String> _splitTags(String raw) {
    if (raw.trim().isEmpty) return <String>[];
    return raw
        .split(RegExp(r'[,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static bool _truthy(String v) {
    final t = v.trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'yes' || t == 'ya';
  }

  static String _hostOf(String url) {
    try {
      final u = Uri.parse(url.contains('://') ? url : 'http://$url');
      if (u.host.isNotEmpty) return u.host;
    } catch (_) {}
    return url;
  }

  static _Table _table(String content) {
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      throw ImportException('File CSV kosong atau tidak terbaca.');
    }
    final header = _Header(rows.first.map((h) => h.trim()).toList());
    return _Table(header, rows.sublist(1));
  }

  /// Parser CSV RFC-4180 sederhana: dukung kutip ganda, koma & newline
  /// di dalam kutipan, serta escape "" untuk tanda kutip literal.
  static List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    final s = input;
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(c);
        i++;
        continue;
      }
      if (c == '"') {
        inQuotes = true;
        i++;
        continue;
      }
      if (c == ',') {
        row.add(field.toString());
        field = StringBuffer();
        i++;
        continue;
      }
      if (c == '\r') {
        if (i + 1 < s.length && s[i + 1] == '\n') i++;
        row.add(field.toString());
        field = StringBuffer();
        rows.add(row);
        row = <String>[];
        i++;
        continue;
      }
      if (c == '\n') {
        row.add(field.toString());
        field = StringBuffer();
        rows.add(row);
        row = <String>[];
        i++;
        continue;
      }
      field.write(c);
      i++;
    }
    if (field.length > 0 || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows
        .where((r) => !(r.length == 1 && r[0].trim().isEmpty))
        .toList();
  }
}

class _Header {
  final List<String> names;
  late final List<String> _lower =
      names.map((e) => e.toLowerCase()).toList();
  _Header(this.names);

  /// Index kolom pertama yang cocok salah satu kandidat (case-insensitive).
  int find(List<String> candidates) {
    for (final cand in candidates) {
      final idx = _lower.indexOf(cand.toLowerCase());
      if (idx >= 0) return idx;
    }
    return -1;
  }
}

class _Table {
  final _Header header;
  final List<List<String>> rows;
  _Table(this.header, this.rows);
}
