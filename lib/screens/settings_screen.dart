import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import '../services/import_service.dart';
import '../services/update_service.dart';
import '../services/vault_controller.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatelessWidget {
  final VaultController controller;
  final SettingsController settings;
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _changePassword(BuildContext context) async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Ubah master password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Master password lama',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Master password baru',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Konfirmasi password baru',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final oldPw = oldCtrl.text;
                final newPw = newCtrl.text;
                if (newPw.length < 8) {
                  setState(() => error = 'Password baru minimal 8 karakter.');
                  return;
                }
                if (newPw != confirmCtrl.text) {
                  setState(() => error = 'Konfirmasi tidak cocok.');
                  return;
                }
                final ok = await controller.verifyPassword(oldPw);
                if (!ok) {
                  setState(() => error = 'Password lama salah.');
                  return;
                }
                await controller.changeMasterPassword(newPw);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      _snack(context, 'Master password berhasil diubah.');
    }
  }

  // ── B4: Impor dari file (Chrome / Bitwarden / LastPass / 1Password / KeePass / CSV) ──
  Future<void> _importFromFile(BuildContext context) async {
    const typeGroup = XTypeGroup(
      label: 'Data password',
      extensions: ['csv', 'json'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      if (context.mounted) _snack(context, 'Gagal membaca file.');
      return;
    }

    ImportResult res;
    try {
      res = ImportService.parse(content, fileName: file.name);
    } on ImportException catch (e) {
      if (context.mounted) _snack(context, 'Impor gagal: ${e.message}');
      return;
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Impor gagal: format file tidak dikenali.');
      }
      return;
    }

    if (!context.mounted) return;
    if (res.entries.isEmpty) {
      _snack(context, 'Tidak ada entry yang bisa diimpor dari file ini.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi impor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Format terdeteksi: ${res.format.label}'),
            const SizedBox(height: 8),
            Text('${res.count} entry akan ditambahkan ke vault.'),
            if (res.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Catatan (${res.warnings.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Text(
                    res.warnings.take(20).join('\n'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Impor ${res.count}'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;
    await controller.addEntries(res.entries);
    if (context.mounted) {
      _snack(context, '${res.count} entry berhasil diimpor.');
    }
  }

  // ── D/W6: Cek & pasang pembaruan dari GitHub Releases ──
  Future<void> _checkForUpdate(BuildContext context) async {
    final svc = UpdateService();
    // Indikator loading saat mengecek.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Mengecek pembaruan…'),
          ],
        ),
      ),
    );

    UpdateInfo? info;
    String? error;
    try {
      info = await svc.checkForUpdate();
    } on UpdateException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Gagal mengecek pembaruan: $e';
    }

    if (!context.mounted) {
      svc.dispose();
      return;
    }
    Navigator.of(context).pop(); // tutup loading

    if (error != null) {
      _snack(context, error);
      svc.dispose();
      return;
    }
    if (info == null) {
      _snack(context, 'Kamu sudah memakai versi terbaru.');
      svc.dispose();
      return;
    }

    final update = info;
    final wantInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Versi ${update.version} tersedia'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
          child: SingleChildScrollView(
            child: Text(
              update.releaseNotes.trim().isEmpty
                  ? 'Tidak ada catatan rilis.'
                  : update.releaseNotes.trim(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
              svc.openReleasePage(update.htmlUrl);
            },
            child: const Text('Buka di browser'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Nanti'),
          ),
          if (update.hasInstaller)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Unduh & pasang'),
            ),
        ],
      ),
    );

    if (wantInstall != true || !context.mounted) {
      svc.dispose();
      return;
    }

    // Dialog progress unduhan.
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Mengunduh pembaruan'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text(value == null
                  ? 'Menyiapkan…'
                  : '${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );

    try {
      final file = await svc.downloadInstaller(
        update,
        onProgress: (received, total) {
          progress.value = total > 0 ? received / total : null;
        },
      );
      if (context.mounted) Navigator.of(context).pop(); // tutup progress
      // Jalankan installer lalu keluar dari app (exit(0) di dalam service).
      await svc.launchInstallerAndExit(file);
    } on UpdateException catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _snack(context, e.message);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _snack(context, 'Gagal mengunduh: $e');
      }
    } finally {
      progress.dispose();
      svc.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final s = settings.settings;
          return ListView(
            children: [
              const ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Passman'),
                subtitle: Text(
                    'Password manager lokal terenkripsi (AES-256 + Argon2id).'),
              ),
              const Divider(),

              // ── Keamanan & otomatis ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Keamanan & otomatis',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Auto-lock saat idle'),
                subtitle: Text(s.autoLockMinutes <= 0
                    ? 'Nonaktif'
                    : 'Kunci setelah ${s.autoLockMinutes} menit tanpa aktivitas'),
                trailing: DropdownButton<int>(
                  value: s.autoLockMinutes,
                  items: const [0, 1, 2, 5, 10, 15, 30]
                      .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m == 0 ? 'Nonaktif' : '$m mnt')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      settings.update(s.copyWith(autoLockMinutes: v));
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_off_outlined),
                title: const Text('Hapus clipboard otomatis'),
                subtitle: Text(s.clipboardClearSeconds <= 0
                    ? 'Nonaktif'
                    : 'Bersihkan ${s.clipboardClearSeconds} detik setelah copy password'),
                trailing: DropdownButton<int>(
                  value: s.clipboardClearSeconds,
                  items: const [0, 10, 20, 30, 60]
                      .map((sec) => DropdownMenuItem(
                          value: sec,
                          child: Text(sec == 0 ? 'Nonaktif' : '$sec dtk')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      settings.update(s.copyWith(clipboardClearSeconds: v));
                    }
                  },
                ),
              ),
              const _LaunchAtStartupTile(),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Ubah master password'),
                subtitle:
                    const Text('Re-enkripsi seluruh vault dengan kunci baru.'),
                onTap: () => _changePassword(context),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Kunci sekarang'),
                subtitle: const Text('Tutup vault dan kembali ke layar kunci.'),
                onTap: () {
                  Navigator.of(context).pop();
                  controller.lock();
                },
              ),
              const Divider(),

              // ── Default generator (acak) ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Default generator password',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                title: const Text('Panjang'),
                subtitle: Slider(
                  min: 8,
                  max: 40,
                  divisions: 32,
                  value: s.genLength.clamp(8, 40).toDouble(),
                  label: '${s.genLength}',
                  onChanged: (v) =>
                      settings.update(s.copyWith(genLength: v.round())),
                ),
                trailing: Text('${s.genLength}'),
              ),
              SwitchListTile(
                title: const Text('Huruf besar (A-Z)'),
                value: s.genUpper,
                onChanged: (v) => settings.update(s.copyWith(genUpper: v)),
              ),
              SwitchListTile(
                title: const Text('Angka (0-9)'),
                value: s.genDigits,
                onChanged: (v) => settings.update(s.copyWith(genDigits: v)),
              ),
              SwitchListTile(
                title: const Text('Simbol (!@#\$...)'),
                value: s.genSymbols,
                onChanged: (v) => settings.update(s.copyWith(genSymbols: v)),
              ),
              const Divider(),

              // ── Default generator (passphrase) ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Default passphrase',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                title: const Text('Jumlah kata'),
                subtitle: Slider(
                  min: 3,
                  max: 12,
                  divisions: 9,
                  value: s.genPhWords.clamp(3, 12).toDouble(),
                  label: '${s.genPhWords}',
                  onChanged: (v) =>
                      settings.update(s.copyWith(genPhWords: v.round())),
                ),
                trailing: Text('${s.genPhWords}'),
              ),
              ListTile(
                title: const Text('Pemisah kata'),
                trailing: DropdownButton<String>(
                  value: const ['-', '.', '_', ' ', '']
                          .contains(s.genPhSeparator)
                      ? s.genPhSeparator
                      : '-',
                  items: const [
                    DropdownMenuItem(value: '-', child: Text('Strip ( - )')),
                    DropdownMenuItem(value: '.', child: Text('Titik ( . )')),
                    DropdownMenuItem(
                        value: '_', child: Text('Garis bawah ( _ )')),
                    DropdownMenuItem(value: ' ', child: Text('Spasi')),
                    DropdownMenuItem(value: '', child: Text('Tanpa')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      settings.update(s.copyWith(genPhSeparator: v));
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Huruf awal kapital'),
                value: s.genPhCapitalize,
                onChanged: (v) =>
                    settings.update(s.copyWith(genPhCapitalize: v)),
              ),
              SwitchListTile(
                title: const Text('Sisipkan angka di akhir'),
                value: s.genPhNumber,
                onChanged: (v) => settings.update(s.copyWith(genPhNumber: v)),
              ),
              SwitchListTile(
                title: const Text('Mode default: passphrase'),
                subtitle: const Text(
                    'Buka dialog generator langsung di mode passphrase.'),
                value: s.genUsePassphrase,
                onChanged: (v) =>
                    settings.update(s.copyWith(genUsePassphrase: v)),
              ),
              const Divider(),

              // ── Impor & data ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Impor & data',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Impor dari file'),
                subtitle: const Text(
                    'Chrome, Bitwarden, LastPass, 1Password, KeePass, atau CSV (.csv / .json).'),
                onTap: () => _importFromFile(context),
              ),
              const Divider(),

              // ── Pembaruan ──
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Pembaruan',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('Cek pembaruan'),
                subtitle: const Text(
                    'Cari versi terbaru dari GitHub Releases lalu pasang otomatis.'),
                onTap: () => _checkForUpdate(context),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// Toggle "Jalankan saat Windows menyala" (launch_at_startup).
/// Dibuat StatefulWidget tersendiri karena status enable/disable bersifat async.
class _LaunchAtStartupTile extends StatefulWidget {
  const _LaunchAtStartupTile();

  @override
  State<_LaunchAtStartupTile> createState() => _LaunchAtStartupTileState();
}

class _LaunchAtStartupTileState extends State<_LaunchAtStartupTile> {
  bool? _enabled; // null = sedang memuat status
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await launchAtStartup.isEnabled();
    if (mounted) setState(() => _enabled = v);
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _enabled = value;
    });
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    final actual = await launchAtStartup.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = actual;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.power_settings_new),
      title: const Text('Jalankan saat Windows menyala'),
      subtitle: const Text(
          'Passman otomatis aktif di system tray saat komputer dinyalakan.'),
      value: _enabled ?? false,
      onChanged: (_enabled == null || _busy) ? null : _toggle,
    );
  }
}
