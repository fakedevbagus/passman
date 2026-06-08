import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/vault_entry.dart';
import '../services/vault_controller.dart';
import '../services/backup_service.dart';
import '../services/csv_service.dart';
import '../services/settings_service.dart';
import '../services/theme_controller.dart';
import '../widgets/totp_code_tile.dart';
import 'entry_form_screen.dart';
import 'health_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, favorites, twofa, weak }

class HomeScreen extends StatefulWidget {
  final VaultController controller;
  final SettingsController settings;
  final ThemeController themeController;
  const HomeScreen({
    super.key,
    required this.controller,
    required this.settings,
    required this.themeController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VaultController get controller => widget.controller;
  SettingsController get settings => widget.settings;

  static const double _kDefaultSidebar = 248;
  static const double _kMinSidebar = 200;
  static const double _kMaxSidebar = 420;

  final _searchCtrl = TextEditingController();
  _Filter _filter = _Filter.all;
  String? _selectedId;
  bool _wide = false;
  double _sidebarWidth = _kDefaultSidebar;
  String? _folder; // B1: filter folder aktif (null = semua)
  String? _tag; // B1: filter tag aktif (null = semua)

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  static bool isWeak(String pw) {
    if (pw.isEmpty) return true;
    var classes = 0;
    if (pw.contains(RegExp(r'[a-z]'))) classes++;
    if (pw.contains(RegExp(r'[A-Z]'))) classes++;
    if (pw.contains(RegExp(r'[0-9]'))) classes++;
    if (pw.contains(RegExp(r'[^A-Za-z0-9]'))) classes++;
    return pw.length < 12 || classes < 3;
  }

  static bool hasTotp(VaultEntry e) => e.totpSecret.trim().isNotEmpty;

  List<VaultEntry> _applyFilter(List<VaultEntry> list) {
    Iterable<VaultEntry> out = list;
    switch (_filter) {
      case _Filter.all:
        break;
      case _Filter.favorites:
        out = out.where((e) => e.favorite);
        break;
      case _Filter.twofa:
        out = out.where(hasTotp);
        break;
      case _Filter.weak:
        out = out.where((e) => isWeak(e.password));
        break;
    }
    if (_folder != null) out = out.where((e) => e.folder == _folder);
    if (_tag != null) out = out.where((e) => e.tags.contains(_tag));
    return out.toList();
  }

  /// B1: pilih kategori dari sidebar (reset folder & tag).
  void _selectFilter(_Filter f) {
    setState(() {
      _filter = f;
      _folder = null;
      _tag = null;
    });
  }

  /// B1: pilih folder dari sidebar (reset kategori & tag).
  void _selectFolder(String? folder) {
    setState(() {
      _folder = folder;
      _filter = _Filter.all;
      _tag = null;
    });
  }

  /// B1: terapkan filter tag (mis. dari klik chip tag di detail).
  void _applyTagFilter(String t) {
    setState(() {
      _tag = t;
      if (_wide) _selectedId = null;
    });
  }

  VaultEntry? _resolveById(String? id) {
    if (id == null) return null;
    for (final e in controller.allEntries) {
      if (e.id == id) return e;
    }
    return null;
  }

  (IconData, String) _themeMeta() {
    switch (widget.themeController.mode) {
      case ThemeMode.system:
        return (Icons.brightness_auto_outlined, 'Tema: Sistem');
      case ThemeMode.light:
        return (Icons.light_mode_outlined, 'Tema: Terang');
      case ThemeMode.dark:
        return (Icons.dark_mode_outlined, 'Tema: Gelap');
    }
  }

  // ---------- actions ----------
  Future<void> _openForm({VaultEntry? entry}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EntryFormScreen(
        controller: controller,
        settings: settings,
        entry: entry,
      ),
    ));
  }

  void _snack(String msg, {int seconds = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: seconds)),
    );
  }

  Future<void> _copy(String label, String value,
      {bool autoClear = false}) async {
    if (value.isEmpty) {
      _snack('$label kosong.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    final secs = settings.settings.clipboardClearSeconds;
    final willClear = autoClear && secs > 0;
    if (mounted) {
      _snack(
        willClear ? '$label disalin (auto-hapus $secs detik).' : '$label disalin.',
        seconds: 2,
      );
    }
    if (willClear) {
      Future.delayed(Duration(seconds: secs), () async {
        final data = await Clipboard.getData('text/plain');
        if (data?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      });
    }
  }

  Future<void> _export() async {
    try {
      final path = await BackupService().exportBackup();
      if (!mounted) return;
      _snack(
        path == null ? 'Dibatalkan / vault kosong.' : 'Backup tersimpan:\n$path',
        seconds: 5,
      );
    } catch (e) {
      if (mounted) _snack('Gagal: $e');
    }
  }

  Future<void> _import() async {
    try {
      final ok = await BackupService().importBackup();
      if (!ok) return;
      controller.lock();
      if (mounted) {
        _snack('Backup di-import. Unlock dengan password backup.');
      }
    } catch (e) {
      if (mounted) _snack('Gagal: $e');
    }
  }

  Future<void> _exportCsv() async {
    try {
      final path = await CsvService().exportToFile(controller.allEntries);
      if (!mounted) return;
      _snack(
        path == null
            ? 'Dibatalkan / vault kosong.'
            : 'CSV tersimpan:\n$path\n\u26a0\ufe0f File ini PLAINTEXT — hapus setelah dipakai.',
        seconds: 6,
      );
    } catch (e) {
      if (mounted) _snack('Gagal: $e');
    }
  }

  Future<void> _importCsv() async {
    try {
      final result = await CsvService().importFromFile();
      if (result == null) return;
      if (result.entries.isEmpty) {
        if (mounted) _snack('Tidak ada data yang bisa diimpor dari CSV itu.');
        return;
      }
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Konfirmasi import CSV'),
          content: Text(
            '${result.entries.length} kredensial akan ditambahkan ke vault.'
            '${result.skipped > 0 ? '\n${result.skipped} baris dilewati (kosong).' : ''}'
            '\n\nCatatan: file CSV tidak terenkripsi. Sebaiknya hapus file '
            'tersebut setelah import selesai.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await controller.addEntries(result.entries);
      if (mounted) {
        _snack(
          '${result.entries.length} kredensial diimpor. '
          'Jangan lupa hapus file CSV-nya untuk keamanan.',
          seconds: 6,
        );
      }
    } catch (e) {
      if (mounted) _snack('Gagal: $e');
    }
  }

  void _openHealth() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            HealthScreen(controller: controller, settings: settings),
      ));

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(controller: controller, settings: settings),
      ));

  Future<void> _deleteEntry(VaultEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus entry?'),
        content: Text('“${e.title}” akan dihapus permanen. '
            'Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteEntry(e.id);
      if (mounted) setState(() => _selectedId = null);
    }
  }

  void _onTapEntry(VaultEntry e) {
    if (_wide) {
      setState(() => _selectedId = e.id);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
              title: Text(e.title.isEmpty ? '(Tanpa judul)' : e.title)),
          body: ListenableBuilder(
            listenable: controller,
            builder: (ctx, _) {
              final cur = _resolveById(e.id);
              if (cur == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                });
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.all(20),
                child: EntryDetailView(
                  controller: controller,
                  entry: cur,
                  onCopy: (l, v, a) => _copy(l, v, autoClear: a),
                  onEdit: () => _openForm(entry: cur),
                  onDelete: () => _deleteEntry(cur),
                  onToggleFavorite: () => controller.toggleFavorite(cur.id),
                  onTagTap: (t) {
                    Navigator.of(ctx).pop();
                    _applyTagFilter(t);
                  },
                ),
              );
            },
          ),
        ),
      ));
    }
  }

  List<PopupMenuEntry<String>> _importExportItems() => [
        const PopupMenuItem(
          value: 'export',
          child: Row(children: [
            Icon(Icons.backup_outlined),
            SizedBox(width: 12),
            Text('Export backup (terenkripsi)'),
          ]),
        ),
        const PopupMenuItem(
          value: 'import',
          child: Row(children: [
            Icon(Icons.settings_backup_restore_outlined),
            SizedBox(width: 12),
            Text('Import backup'),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'export_csv',
          child: Row(children: [
            Icon(Icons.file_download_outlined),
            SizedBox(width: 12),
            Text('Export CSV (plaintext)'),
          ]),
        ),
        const PopupMenuItem(
          value: 'import_csv',
          child: Row(children: [
            Icon(Icons.file_upload_outlined),
            SizedBox(width: 12),
            Text('Import CSV'),
          ]),
        ),
      ];

  void _onImportExport(String v) {
    switch (v) {
      case 'export':
        _export();
        break;
      case 'import':
        _import();
        break;
      case 'export_csv':
        _exportCsv();
        break;
      case 'import_csv':
        _importCsv();
        break;
    }
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, c) {
            _wide = c.maxWidth >= 880;
            return _wide ? _wideLayout(context) : _narrowLayout(context);
          },
        );
      },
    );
  }

  Widget _wideLayout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = cs.outlineVariant.withOpacity(0.4);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _sidebar(context, width: _sidebarWidth),
            _resizeHandle(context),
            SizedBox(
                width: 360,
                child: _masterPane(context, showFilters: false)),
            VerticalDivider(width: 1, color: divider),
            Expanded(child: _detailPane(context)),
          ],
        ),
      ),
    );
  }

  /// Garis pemisah yang bisa di-drag untuk melebarkan/menyempitkan sidebar.
  /// Double-click untuk reset ke lebar default.
  Widget _resizeHandle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          setState(() {
            _sidebarWidth = (_sidebarWidth + d.delta.dx)
                .clamp(_kMinSidebar, _kMaxSidebar)
                .toDouble();
          });
        },
        onDoubleTap: () =>
            setState(() => _sidebarWidth = _kDefaultSidebar),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(width: 1, color: cs.outlineVariant.withOpacity(0.4)),
          ),
        ),
      ),
    );
  }

  Widget _narrowLayout(BuildContext context) {
    final theme = _themeMeta();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(children: [
          _logoMark(28),
          const SizedBox(width: 10),
          const Text('Passman'),
        ]),
        actions: [
          IconButton(
            icon: Icon(theme.$1),
            tooltip: theme.$2,
            onPressed: widget.themeController.cycle,
          ),
          IconButton(
            icon: const Icon(Icons.health_and_safety_outlined),
            tooltip: 'Kesehatan password',
            onPressed: _openHealth,
          ),
          PopupMenuButton<String>(
            tooltip: 'Import / Export',
            icon: const Icon(Icons.more_vert),
            onSelected: _onImportExport,
            itemBuilder: (_) => _importExportItems(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Kunci',
            onPressed: controller.lock,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: _masterPane(context, showFilters: true),
    );
  }

  // ---------- sidebar ----------
  Widget _logoMark(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B54E8), Color(0xFF3A2FB0)],
        ),
      ),
      child: Icon(Icons.lock_rounded, color: Colors.white, size: size * 0.52),
    );
  }

  Widget _sidebar(BuildContext context, {required double width}) {
    final cs = Theme.of(context).colorScheme;
    final all = controller.allEntries;
    final counts = {
      _Filter.all: all.length,
      _Filter.favorites: all.where((e) => e.favorite).length,
      _Filter.twofa: all.where(hasTotp).length,
      _Filter.weak: all.where((e) => isWeak(e.password)).length,
    };
    final folders = controller.allFolders;
    final folderCounts = <String, int>{
      for (final f in folders) f: all.where((e) => e.folder == f).length,
    };
    final theme = _themeMeta();
    return Container(
      width: width,
      color: Color.alphaBlend(cs.primary.withOpacity(0.03), cs.surface),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              _logoMark(34),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Passman',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _navItem(_Filter.all, 'Semua', Icons.vpn_key_outlined,
                    counts[_Filter.all]!),
                _navItem(_Filter.favorites, 'Favorit', Icons.star_outline,
                    counts[_Filter.favorites]!),
                _navItem(_Filter.twofa, 'Dengan 2FA', Icons.shield_outlined,
                    counts[_Filter.twofa]!),
                _navItem(_Filter.weak, 'Perlu perhatian',
                    Icons.warning_amber_rounded, counts[_Filter.weak]!),
                if (folders.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Text('FOLDER',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: cs.onSurfaceVariant)),
                  ),
                  for (final f in folders)
                    _folderNavItem(f, folderCounts[f] ?? 0),
                ],
              ],
            ),
          ),
          Divider(color: cs.outlineVariant.withOpacity(0.5)),
          const SizedBox(height: 4),
          _footerItem(theme.$1, theme.$2, widget.themeController.cycle),
          _footerItem(Icons.health_and_safety_outlined,
              'Kesehatan password', _openHealth),
          PopupMenuButton<String>(
            tooltip: 'Import / Export',
            position: PopupMenuPosition.under,
            onSelected: _onImportExport,
            itemBuilder: (_) => _importExportItems(),
            child: _footerRow(Icons.import_export, 'Import / Export'),
          ),
          _footerItem(Icons.settings_outlined, 'Pengaturan', _openSettings),
          _footerItem(Icons.lock_outline, 'Kunci sekarang', controller.lock),
        ],
      ),
    );
  }

  Widget _navItem(_Filter filter, String label, IconData icon, int count) {
    final cs = Theme.of(context).colorScheme;
    final sel = _filter == filter && _folder == null && _tag == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: sel
            ? cs.primaryContainer.withOpacity(0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectFilter(filter),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(icon,
                  size: 20,
                  color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color:
                            sel ? cs.onPrimaryContainer : cs.onSurface)),
              ),
              if (count > 0)
                Text('$count',
                    style: TextStyle(
                        color: sel
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _folderNavItem(String folder, int count) {
    final cs = Theme.of(context).colorScheme;
    final sel = _folder == folder;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: sel ? cs.primaryContainer.withOpacity(0.6) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectFolder(folder),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(Icons.folder_outlined,
                  size: 19,
                  color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color: sel ? cs.onPrimaryContainer : cs.onSurface)),
              ),
              if (count > 0)
                Text('$count',
                    style: TextStyle(
                        color: sel
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _footerItem(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: _footerRow(icon, label),
      ),
    );
  }

  Widget _footerRow(IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface)),
        ),
      ]),
    );
  }

  // ---------- master ----------
  Widget _masterPane(BuildContext context, {required bool showFilters}) {
    final entries = _applyFilter(controller.entries);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: controller.setQuery,
                decoration: const InputDecoration(
                  hintText: 'Cari...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            if (!showFilters) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah'),
              ),
            ],
          ]),
        ),
        if (showFilters) _filterChips(context),
        if (_tag != null) _activeTagBanner(context),
        Expanded(
          child: entries.isEmpty
              ? _emptyList(context)
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return _EntryListTile(
                      entry: e,
                      selected: _wide && e.id == _selectedId,
                      onTap: () => _onTapEntry(e),
                      onCopyPassword: () =>
                          _copy('Password', e.password, autoClear: true),
                      onToggleFavorite: () => controller.toggleFavorite(e.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChips(BuildContext context) {
    final all = controller.allEntries;
    final data = [
      (_Filter.all, 'Semua', all.length),
      (_Filter.favorites, 'Favorit', all.where((e) => e.favorite).length),
      (_Filter.twofa, 'Dengan 2FA', all.where(hasTotp).length),
      (_Filter.weak, 'Perlu perhatian', all.where((e) => isWeak(e.password)).length),
    ];
    final folders = controller.allFolders;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final d in data)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${d.$2} (${d.$3})'),
                  selected:
                      _filter == d.$1 && _folder == null && _tag == null,
                  onSelected: (_) => _selectFilter(d.$1),
                ),
              ),
            for (final f in folders)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(f),
                  selected: _folder == f,
                  onSelected: (_) => _selectFolder(_folder == f ? null : f),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _activeTagBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: Icon(Icons.label, size: 16, color: cs.primary),
          label: Text('Tag: $_tag'),
          onDeleted: () => setState(() => _tag = null),
        ),
      ),
    );
  }

  Widget _emptyList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final msg = _filter == _Filter.all
        ? 'Belum ada kredensial.\nTekan “Tambah” untuk mulai.'
        : 'Tidak ada entry di filter ini.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ---------- detail ----------
  Widget _detailPane(BuildContext context) {
    final selected = _resolveById(_selectedId);
    if (selected == null) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.password_outlined,
                size: 56, color: cs.onSurfaceVariant.withOpacity(0.6)),
            const SizedBox(height: 14),
            Text('Pilih entry untuk melihat detail',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(28),
      child: EntryDetailView(
        key: ValueKey(selected.id),
        controller: controller,
        entry: selected,
        onCopy: (l, v, a) => _copy(l, v, autoClear: a),
        onEdit: () => _openForm(entry: selected),
        onDelete: () => _deleteEntry(selected),
        onToggleFavorite: () => controller.toggleFavorite(selected.id),
        onTagTap: _applyTagFilter,
      ),
    );
  }
}

// =====================================================================
//  Master list tile
// =====================================================================
class _EntryListTile extends StatelessWidget {
  final VaultEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopyPassword;
  final VoidCallback onToggleFavorite;
  const _EntryListTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onCopyPassword,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasTotp = entry.totpSecret.trim().isNotEmpty;
    return Material(
      color: selected
          ? cs.primaryContainer.withOpacity(0.55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _Avatar(text: entry.title, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title.isEmpty ? '(Tanpa judul)' : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (entry.username.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(entry.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  if (entry.type != EntryType.login ||
                      entry.folder.trim().isNotEmpty ||
                      entry.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        if (entry.type != EntryType.login) ...[
                          Icon(entryTypeIcon(entry.type),
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(entry.type.label,
                              style: tt.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                          if (entry.folder.trim().isNotEmpty ||
                              entry.tags.isNotEmpty)
                            const SizedBox(width: 8),
                        ],
                        if (entry.folder.trim().isNotEmpty) ...[
                          Icon(Icons.folder_outlined,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(entry.folder.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                        ],
                        if (entry.folder.trim().isNotEmpty &&
                            entry.tags.isNotEmpty)
                          const SizedBox(width: 8),
                        if (entry.tags.isNotEmpty) ...[
                          Icon(Icons.label_outline,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text('${entry.tags.length}',
                              style: tt.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
            if (hasTotp)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.shield_outlined,
                    size: 16, color: cs.onSurfaceVariant),
              ),
            IconButton(
              icon: Icon(entry.favorite ? Icons.star : Icons.star_border,
                  size: 18,
                  color: entry.favorite ? Colors.amber : cs.onSurfaceVariant),
              tooltip: entry.favorite ? 'Hapus favorit' : 'Favoritkan',
              onPressed: onToggleFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Salin password',
              onPressed: onCopyPassword,
            ),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================
//  Detail view (dipakai di panel kanan & halaman detail mobile)
// =====================================================================
class EntryDetailView extends StatefulWidget {
  final VaultController controller; // B3: untuk cek kebocoran per-entry
  final VaultEntry entry;
  final void Function(String label, String value, bool autoClear) onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final void Function(String tag) onTagTap;
  const EntryDetailView({
    super.key,
    required this.controller,
    required this.entry,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onTagTap,
  });

  @override
  State<EntryDetailView> createState() => _EntryDetailViewState();
}

class _EntryDetailViewState extends State<EntryDetailView> {
  bool _reveal = false;
  final Set<int> _revealedCustom = <int>{}; // B2: reveal per custom field

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final e = widget.entry;
    final hasTotp = e.totpSecret.trim().isNotEmpty;
    return ListView(
      children: [
        Row(children: [
          _Avatar(text: e.title, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title.isEmpty ? '(Tanpa judul)' : e.title,
                    style: tt.headlineSmall),
                if (e.url.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.url,
                        style: tt.bodyMedium?.copyWith(color: cs.primary)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(e.favorite ? Icons.star : Icons.star_border,
                color: e.favorite ? Colors.amber : cs.onSurfaceVariant),
            tooltip: e.favorite ? 'Hapus favorit' : 'Favoritkan',
            onPressed: widget.onToggleFavorite,
          ),
        ]),
        const SizedBox(height: 22),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: widget.onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
            label: Text('Hapus', style: TextStyle(color: cs.error)),
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.error.withOpacity(0.5))),
          ),
        ]),
        ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar:
                    Icon(entryTypeIcon(e.type), size: 16, color: cs.primary),
                label: Text(e.type.label),
              ),
              if (e.folder.trim().isNotEmpty)
                Chip(
                  avatar: Icon(Icons.folder_outlined,
                      size: 16, color: cs.onSurfaceVariant),
                  label: Text(e.folder.trim()),
                ),
              for (final t in e.tags)
                ActionChip(
                  avatar:
                      Icon(Icons.label_outline, size: 16, color: cs.primary),
                  label: Text(t),
                  onPressed: () => widget.onTagTap(t),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        _fieldCard(context, children: [
          _field(context,
              icon: Icons.person_outline,
              label: 'Username',
              value: e.username.isEmpty ? '—' : e.username,
              onCopy: e.username.isEmpty
                  ? null
                  : () => widget.onCopy('Username', e.username, false)),
          const Divider(height: 1),
          _passwordField(context, e),
          if (e.url.isNotEmpty) ...[
            const Divider(height: 1),
            _field(context,
                icon: Icons.link,
                label: 'URL',
                value: e.url,
                onCopy: () => widget.onCopy('URL', e.url, false)),
          ],
        ]),
        _breachSection(context, e),
        if (hasTotp) ...[
          const SizedBox(height: 18),
          _sectionLabel(context, 'Autentikasi 2 langkah'),
          const SizedBox(height: 8),
          _fieldCard(context, children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TotpCodeTile(secret: e.totpSecret.trim()),
            ),
          ]),
        ],
        if (e.customFields.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionLabel(context, 'Field tambahan'),
          const SizedBox(height: 8),
          _fieldCard(context, children: [
            for (var i = 0; i < e.customFields.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _customField(context, e.customFields[i], i),
            ],
          ]),
        ],
        if (e.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionLabel(context, 'Catatan'),
          const SizedBox(height: 8),
          _fieldCard(context, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(e.notes),
            ),
          ]),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fieldCard(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _field(BuildContext context,
      {required IconData icon,
      required String label,
      required String value,
      VoidCallback? onCopy}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              SelectableText(value, style: tt.bodyLarge),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Salin',
            onPressed: onCopy,
          ),
      ]),
    );
  }

  Widget _passwordField(BuildContext context, VaultEntry e) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final empty = e.password.isEmpty;
    final shown = empty
        ? '—'
        : (_reveal ? e.password : '•' * e.password.length.clamp(6, 18));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(Icons.lock_outline, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Password',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(shown,
                  style: tt.bodyLarge?.copyWith(
                      fontFamily: 'monospace', letterSpacing: 1)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility,
              size: 18),
          tooltip: _reveal ? 'Sembunyikan' : 'Lihat',
          onPressed: empty ? null : () => setState(() => _reveal = !_reveal),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Salin password',
          onPressed: empty ? null : () => widget.onCopy('Password', e.password, true),
        ),
      ]),
    );
  }

  Widget _customField(BuildContext context, CustomField f, int index) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final empty = f.value.isEmpty;
    final revealed = _revealedCustom.contains(index);
    final shown = empty
        ? '—'
        : (f.secret && !revealed
            ? '•' * f.value.length.clamp(6, 18)
            : f.value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(f.secret ? Icons.lock_outline : Icons.notes,
            size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.label.isEmpty ? 'Field' : f.label,
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              SelectableText(shown,
                  style: f.secret
                      ? tt.bodyLarge?.copyWith(
                          fontFamily: 'monospace', letterSpacing: 1)
                      : tt.bodyLarge),
            ],
          ),
        ),
        if (f.secret)
          IconButton(
            icon: Icon(revealed ? Icons.visibility_off : Icons.visibility,
                size: 18),
            tooltip: revealed ? 'Sembunyikan' : 'Lihat',
            onPressed: empty
                ? null
                : () => setState(() {
                      if (revealed) {
                        _revealedCustom.remove(index);
                      } else {
                        _revealedCustom.add(index);
                      }
                    }),
          ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Salin',
          onPressed: empty
              ? null
              : () => widget.onCopy(
                  f.label.isEmpty ? 'Field' : f.label, f.value, f.secret),
        ),
      ]),
    );
  }

  // B3: panel cek kebocoran password (Have I Been Pwned, k-anonymity).
  Widget _breachSection(BuildContext context, VaultEntry e) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = widget.controller;
    if (e.password.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final checking = c.isCheckingBreach(e.id);
          final checked = c.isBreachChecked(e.id);
          final count = c.breachCountFor(e.id);
          final pwned = checked && count > 0;

          Color bg;
          Color fg;
          Border? border;
          IconData icon;
          String title;
          String subtitle;
          if (checking) {
            bg = cs.surface;
            fg = cs.onSurfaceVariant;
            border = Border.all(color: cs.outlineVariant.withOpacity(0.5));
            icon = Icons.shield_outlined;
            title = 'Mengecek ke Have I Been Pwned\u2026';
            subtitle = 'Sebentar ya.';
          } else if (!checked) {
            bg = cs.surface;
            fg = cs.onSurfaceVariant;
            border = Border.all(color: cs.outlineVariant.withOpacity(0.5));
            icon = Icons.shield_outlined;
            title = 'Cek kebocoran password';
            subtitle =
                'Privat: hanya 5 karakter awal hash yang dikirim (k-anonymity).';
          } else if (pwned) {
            bg = cs.errorContainer;
            fg = cs.onErrorContainer;
            icon = Icons.gpp_bad_outlined;
            title = 'Ketahuan bocor ${_fmtCount(count)}\u00d7';
            subtitle =
                'Password ini muncul di kebocoran data publik. Sebaiknya segera diganti.';
          } else {
            bg = Colors.green.withOpacity(0.14);
            fg = Colors.green.shade700;
            icon = Icons.verified_user_outlined;
            title = 'Tidak ditemukan di kebocoran';
            subtitle = 'Password ini tidak muncul di database HIBP.';
          }

          return Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: border,
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (checking)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: fg),
                  )
                else
                  Icon(icon, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: tt.bodyLarge?.copyWith(
                              color: fg, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: tt.bodySmall
                              ?.copyWith(color: fg.withOpacity(0.9))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!checking)
                  TextButton(
                    onPressed: () => _runBreachCheck(e.id),
                    style: TextButton.styleFrom(foregroundColor: fg),
                    child: Text(checked ? 'Cek lagi' : 'Cek'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtCount(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _runBreachCheck(String id) async {
    try {
      await widget.controller.checkEntryBreach(id);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString())),
      );
    }
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: cs.onSurfaceVariant));
  }
}

// =====================================================================
//  Avatar dengan inisial + warna unik per entry
// =====================================================================
class _Avatar extends StatelessWidget {
  final String text;
  final double size;
  const _Avatar({required this.text, this.size = 40});

  static const _palettes = [
    [Color(0xFF6366F1), Color(0xFF4338CA)],
    [Color(0xFF0EA5E9), Color(0xFF0369A1)],
    [Color(0xFF10B981), Color(0xFF047857)],
    [Color(0xFFF59E0B), Color(0xFFB45309)],
    [Color(0xFFEC4899), Color(0xFFBE185D)],
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    final ch = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final idx =
        trimmed.isEmpty ? 0 : (trimmed.codeUnitAt(0) + trimmed.length) % _palettes.length;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _palettes[idx],
        ),
      ),
      child: Text(ch,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.42)),
    );
  }
}
