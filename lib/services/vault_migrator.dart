import '../models/vault_entry.dart';

/// Dilempar saat file vault dibuat oleh versi aplikasi yang LEBIH BARU
/// (skema di disk > skema yang didukung build ini). Ini BUKAN korupsi dan
/// BUKAN password salah — user cuma perlu update aplikasinya.
class SchemaTooNewException implements Exception {
  final int fileVersion;
  final int appVersion;
  const SchemaTooNewException(this.fileVersion, this.appVersion);
  @override
  String toString() =>
      'Vault dibuat oleh versi Passman yang lebih baru (skema v$fileVersion > v$appVersion).';
}

/// Fungsi migrasi: ubah payload versi N menjadi payload versi N+1.
typedef SchemaMigration = Map<String, dynamic> Function(
    Map<String, dynamic> data);

/// Framework versioning + migrasi untuk payload (terdekripsi) vault.
///
/// Payload disimpan sebagai envelope berversi:
///   { "schemaVersion": <int>, "entries": [ ... ] }
///
/// Versi 0 (LEGACY) = payload berupa List<entry> polos tanpa envelope
/// (format sebelum C1). Akan otomatis dimigrasi ke versi terbaru saat unlock.
///
/// Cara menambah versi baru:
///   1. Naikkan [currentVersion].
///   2. Tambahkan fungsi migrasi `_vXToVY` dan daftarkan di [_migrations].
///   3. Setiap fungsi migrasi HARUS menaikkan field 'schemaVersion'.
class VaultSchema {
  VaultSchema._();

  /// Versi skema yang didukung build aplikasi saat ini.
  /// v1 (C1) = envelope berversi. v2 (B1) = entry punya folder/tags/favorite.
  /// v3 (B2) = entry punya type + customFields.
  static const int currentVersion = 3;

  /// Registry migrasi. Key = versi ASAL, value = fungsi ke versi (asal + 1).
  /// Migrasi dijalankan berurutan: v0 -> v1 -> v2 -> ... -> currentVersion.
  static final Map<int, SchemaMigration> _migrations = {
    0: _v0ToV1,
    1: _v1ToV2,
    2: _v2ToV3,
    // 3: _v3ToV4,  // <- slot untuk perubahan model berikutnya
  };

  /// Bungkus hasil dekripsi mentah menjadi envelope berversi yang ternormalisasi.
  /// Melempar [FormatException] kalau strukturnya tidak dikenal (-> dianggap korup).
  static Map<String, dynamic> _normalize(dynamic decoded) {
    // Legacy v0: payload berupa List<entry> polos.
    if (decoded is List) {
      return {'schemaVersion': 0, 'entries': decoded};
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final v = map['schemaVersion'];
      if (v is int && map['entries'] is List) {
        return map;
      }
    }
    throw const FormatException('Struktur payload vault tidak dikenal.');
  }

  /// Jalankan migrasi berurutan sampai [currentVersion].
  /// Mengembalikan (payload terkini, apakah ADA migrasi yang dijalankan).
  ///
  /// Melempar:
  ///  - [SchemaTooNewException] kalau versi file > currentVersion.
  ///  - [FormatException] kalau struktur/jalur migrasi tidak valid.
  static (Map<String, dynamic>, bool) migrate(dynamic decoded) {
    var data = _normalize(decoded);
    var version = data['schemaVersion'] as int;

    if (version > currentVersion) {
      throw SchemaTooNewException(version, currentVersion);
    }

    var didMigrate = false;
    while (version < currentVersion) {
      final step = _migrations[version];
      if (step == null) {
        throw FormatException('Tidak ada jalur migrasi dari skema v$version.');
      }
      data = step(data);
      final next = data['schemaVersion'];
      if (next is! int || next <= version) {
        throw FormatException(
            'Migrasi dari skema v$version menghasilkan versi tidak valid.');
      }
      version = next;
      didMigrate = true;
    }
    return (data, didMigrate);
  }

  /// Decode daftar entry dari payload (yang sudah dimigrasi ke currentVersion).
  static List<VaultEntry> decodeEntries(Map<String, dynamic> data) {
    final list = data['entries'] as List<dynamic>;
    return list
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Bangun envelope versi TERKINI dari daftar entry (untuk ditulis ke disk).
  static Map<String, dynamic> encode(List<VaultEntry> entries) => {
        'schemaVersion': currentVersion,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  // ----------------- migrasi konkret -----------------

  /// v0 (List polos / legacy) -> v1 (envelope berversi).
  /// Struktur tiap entry TIDAK berubah; hanya membungkus + memberi versi.
  static Map<String, dynamic> _v0ToV1(Map<String, dynamic> data) {
    return {
      'schemaVersion': 1,
      'entries': data['entries'],
    };
  }

  /// v1 -> v2 (B1): tambah field folder/tags/favorite ke tiap entry dengan
  /// nilai default yang aman. Idempotent (pakai ??= jadi tidak menimpa
  /// data yang sudah ada).
  static Map<String, dynamic> _v1ToV2(Map<String, dynamic> data) {
    final entries = (data['entries'] as List<dynamic>).map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      map['folder'] ??= '';
      map['tags'] ??= <String>[];
      map['favorite'] ??= false;
      return map;
    }).toList();
    return {
      'schemaVersion': 2,
      'entries': entries,
    };
  }

  /// v2 -> v3 (B2): tambah field type/customFields ke tiap entry dengan nilai
  /// default yang aman. Idempotent (pakai ??= jadi tidak menimpa data yang ada).
  static Map<String, dynamic> _v2ToV3(Map<String, dynamic> data) {
    final entries = (data['entries'] as List<dynamic>).map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      map['type'] ??= 'login';
      map['customFields'] ??= <dynamic>[];
      return map;
    }).toList();
    return {
      'schemaVersion': 3,
      'entries': entries,
    };
  }
}
