import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import '../models/vault_entry.dart';
import 'crypto_service.dart';
import 'vault_migrator.dart';

/// Wadah kunci aktif selama sesi (key + salt).
class SecretKeyHolder {
  final SecretKey key;
  final List<int> salt;
  SecretKeyHolder({required this.key, required this.salt});
}

/// Exception dasar untuk semua kegagalan terkait vault.
/// `toString()` mengembalikan pesan yang AMAN ditampilkan ke user
/// (tidak pernah membocorkan password/kunci).
class VaultException implements Exception {
  final String message;
  const VaultException(this.message);
  @override
  String toString() => message;
}

/// Master password salah (autentikasi MAC AES-GCM gagal).
class WrongPasswordException extends VaultException {
  const WrongPasswordException() : super('Master password salah.');
}

/// File vault rusak dan tidak ada backup valid untuk dipulihkan.
class VaultCorruptException extends VaultException {
  const VaultCorruptException()
      : super(
            'File vault rusak dan tidak ada backup valid untuk dipulihkan.');
}

/// Mengelola baca/tulis file vault terenkripsi di disk.
///
/// Format FILE (lapisan luar, tidak berubah sejak awal):
///   { "salt": "<base64>", "data": { nonce, cipherText, mac } }
///
/// Isi `data` adalah hasil enkripsi dari sebuah PAYLOAD JSON. Sejak C1,
/// payload memakai envelope berversi (lihat [VaultSchema]):
///   { "schemaVersion": <int>, "entries": [ ... ] }
/// Payload lama (List<entry> polos) dianggap skema v0 dan otomatis dimigrasi
/// saat unlock.
class VaultStorage {
  final CryptoService _crypto = CryptoService();

  Future<File> _vaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/passman_vault.json');
  }

  Future<Directory> _backupDir() async {
    final dir = await getApplicationSupportDirectory();
    final backupDir = Directory('${dir.path}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<bool> vaultExists() async => (await _vaultFile()).exists();

  /// Buat vault baru (saat user pertama kali set master password).
  Future<SecretKeyHolder> createVault({
    required String masterPassword,
    List<VaultEntry> initialEntries = const [],
  }) async {
    final salt = _crypto.newSalt();
    final key = await _crypto.deriveKey(
      masterPassword: masterPassword,
      salt: salt,
    );
    await _writeEntries(key: key, salt: salt, entries: initialEntries);
    return SecretKeyHolder(key: key, salt: salt);
  }

  /// Buka vault & kembalikan entry + key holder.
  /// Melempar [WrongPasswordException] jika password salah,
  /// [VaultCorruptException] jika file/backup rusak,
  /// atau [VaultException] untuk kegagalan lain (IO, belum dibuat,
  /// atau skema file lebih baru dari aplikasi).
  Future<(SecretKeyHolder, List<VaultEntry>)> unlock(
      String masterPassword) async {
    final file = await _vaultFile();

    if (!await file.exists()) {
      throw const VaultException('Vault belum dibuat.');
    }

    // 1) Baca file (IO).
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      throw const VaultException(
          'Gagal membaca file vault. Periksa izin folder atau ruang disk.');
    }

    // 2) Parse struktur; jika korup, coba pulihkan dari backup valid terbaru.
    Map<String, dynamic> raw;
    try {
      raw = _parseVault(content);
    } on FormatException {
      final restored = await _tryRestoreFromBackup(file);
      if (restored == null) {
        throw const VaultCorruptException();
      }
      raw = restored;
    }

    // 3) Decode salt + derive key.
    final List<int> salt;
    try {
      salt = base64Decode(raw['salt'] as String);
    } catch (_) {
      throw const VaultCorruptException();
    }
    final key = await _crypto.deriveKey(
      masterPassword: masterPassword,
      salt: salt,
    );

    // 4) Dekripsi. MAC gagal => password salah. Struktur aneh => korup.
    final String plain;
    try {
      final blob =
          EncryptedBlob.fromJson(raw['data'] as Map<String, dynamic>);
      plain = await _crypto.decrypt(key: key, blob: blob);
    } on SecretBoxAuthenticationError {
      throw const WrongPasswordException();
    } catch (_) {
      throw const VaultCorruptException();
    }

    // 5) Decode payload + jalankan migrasi skema bila perlu.
    //    (Sampai sini MAC sudah valid => password BENAR; masalah struktur di
    //    sini berarti korup, kecuali kasus "skema lebih baru".)
    final List<VaultEntry> entries;
    final bool migrated;
    try {
      final decoded = jsonDecode(plain);
      final (data, didMigrate) = VaultSchema.migrate(decoded);
      entries = VaultSchema.decodeEntries(data);
      migrated = didMigrate;
    } on SchemaTooNewException catch (e) {
      throw VaultException(
          '$e Update Passman ke versi terbaru untuk membukanya.');
    } catch (_) {
      throw const VaultCorruptException();
    }

    final holder = SecretKeyHolder(key: key, salt: salt);

    // 6) Jika skema lama dimigrasi, tulis ulang ke disk dalam format terbaru.
    //    Best-effort: kegagalan menulis TIDAK boleh menggagalkan unlock —
    //    migrasi akan tersimpan otomatis pada penyimpanan berikutnya
    //    (lazy migration).
    if (migrated) {
      try {
        await _writeEntries(key: key, salt: salt, entries: entries);
      } catch (_) {
        // Biarkan; simpan saat operasi save berikutnya.
      }
    }

    return (holder, entries);
  }

  /// Simpan ulang daftar entry (pakai key + salt yang sedang aktif).
  Future<void> save({
    required SecretKeyHolder keyHolder,
    required List<VaultEntry> entries,
  }) async {
    await _writeEntries(
      key: keyHolder.key,
      salt: keyHolder.salt,
      entries: entries,
    );
  }

  // ---------- internal ----------

  /// Validasi struktur file vault (lapisan luar). Lempar FormatException jika tidak valid.
  Map<String, dynamic> _parseVault(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        decoded['salt'] is! String ||
        decoded['data'] is! Map) {
      throw const FormatException('Format vault tidak valid');
    }
    return decoded;
  }

  Future<void> _writeEntries({
    required SecretKey key,
    required List<int> salt,
    required List<VaultEntry> entries,
  }) async {
    try {
      // Selalu tulis dalam envelope berversi TERKINI (lihat VaultSchema).
      final plain = jsonEncode(VaultSchema.encode(entries));
      final blob = await _crypto.encrypt(key: key, plaintext: plain);
      final payload = jsonEncode({
        'salt': base64Encode(salt),
        'data': blob.toJson(),
      });

      final file = await _vaultFile();

      // Auto-backup file lama sebelum ditimpa (best-effort).
      if (await file.exists()) {
        await _backupCurrent(file);
      }

      // Tulis atomik: tulis ke .tmp lalu rename -> tidak korup kalau mati di tengah.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } on VaultException {
      rethrow;
    } catch (_) {
      throw const VaultException(
          'Gagal menyimpan vault. Periksa izin folder atau ruang disk.');
    }
  }

  Future<void> _backupCurrent(File file) async {
    try {
      final backupDir = await _backupDir();
      final ts = DateTime.now()
          .millisecondsSinceEpoch
          .toString()
          .padLeft(15, '0');
      await file.copy('${backupDir.path}/passman_vault_$ts.json');
      await _rotateBackups(backupDir, keep: 5);
    } catch (_) {
      // Backup gagal tidak boleh menggagalkan penyimpanan utama.
    }
  }

  Future<void> _rotateBackups(Directory backupDir, {required int keep}) async {
    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path)); // lama -> baru
    if (files.length <= keep) return;
    for (final f in files.take(files.length - keep)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Coba pulihkan dari backup valid terbaru. Kembalikan JSON terpulihkan, atau null.
  Future<Map<String, dynamic>?> _tryRestoreFromBackup(File vaultFile) async {
    try {
      final backupDir = await _backupDir();
      final backups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // baru -> lama

      for (final backup in backups) {
        final content = await backup.readAsString();
        try {
          final parsed = _parseVault(content);
          // Pulihkan: salin backup valid ke file utama (atomik).
          final tmp = File('${vaultFile.path}.tmp');
          await tmp.writeAsString(content, flush: true);
          if (await vaultFile.exists()) {
            await vaultFile.delete();
          }
          await tmp.rename(vaultFile.path);
          return parsed;
        } on FormatException {
          continue; // backup ini juga korup, coba berikutnya
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
