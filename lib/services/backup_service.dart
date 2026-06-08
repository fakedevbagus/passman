import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// Backup/restore vault lewat dialog file explorer asli (file_selector).
class BackupService {
  Future<File> _vaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/passman_vault.json');
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  /// Export: buka dialog "Save As", salin isi vault ke lokasi pilihan user.
  /// Kembalikan path tujuan, atau null jika dibatalkan / vault kosong.
  Future<String?> exportBackup() async {
    final vault = await _vaultFile();
    if (!await vault.exists()) return null;
    final content = await vault.readAsString();

    final now = DateTime.now();
    final suggested =
        'passman_backup_${now.year}${_two(now.month)}${_two(now.day)}'
        '_${_two(now.hour)}${_two(now.minute)}.json';

    final group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: [group],
    );
    if (location == null) return null; // dibatalkan

    await File(location.path).writeAsString(content, flush: true);
    return location.path;
  }

  /// Import: buka dialog file explorer, validasi, lalu timpa vault.
  /// Kembalikan true jika berhasil, false jika dibatalkan.
  Future<bool> importBackup() async {
    final group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return false; // dibatalkan

    final content = await file.readAsString();
    if (!content.contains('"salt"') || !content.contains('"data"')) {
      throw 'File tidak valid: bukan backup Passman.';
    }

    final vault = await _vaultFile();
    final tmp = File('${vault.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await vault.exists()) await vault.delete();
    await tmp.rename(vault.path);
    return true;
  }
}
