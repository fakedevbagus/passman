import 'package:flutter/material.dart';
import '../models/vault_entry.dart';
import '../services/vault_controller.dart';
import '../services/password_generator.dart';
import '../services/settings_service.dart';
import '../widgets/totp_code_tile.dart';

class EntryFormScreen extends StatefulWidget {
  final VaultController controller;
  final SettingsController settings;
  final VaultEntry? entry;
  const EntryFormScreen({
    super.key,
    required this.controller,
    required this.settings,
    this.entry,
  });
  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  late final _title = TextEditingController(text: widget.entry?.title ?? '');
  late final _username =
      TextEditingController(text: widget.entry?.username ?? '');
  late final _password =
      TextEditingController(text: widget.entry?.password ?? '');
  late final _url = TextEditingController(text: widget.entry?.url ?? '');
  late final _notes = TextEditingController(text: widget.entry?.notes ?? '');
  late final _totp =
      TextEditingController(text: widget.entry?.totpSecret ?? '');
  // B1: organisasi
  late final _folder = TextEditingController(text: widget.entry?.folder ?? '');
  final _tagInput = TextEditingController();
  late final List<String> _tags =
      List<String>.from(widget.entry?.tags ?? const <String>[]);
  late bool _favorite = widget.entry?.favorite ?? false;
  bool _obscure = true;
  // B2: tipe entry + field tambahan
  late EntryType _type = widget.entry?.type ?? EntryType.login;
  late final List<_CustomFieldDraft> _customFields = [
    for (final f in (widget.entry?.customFields ?? const <CustomField>[]))
      _CustomFieldDraft(label: f.label, value: f.value, secret: f.secret),
  ];

  bool get _isEdit => widget.entry != null;

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    _totp.dispose();
    _folder.dispose();
    _tagInput.dispose();
    for (final f in _customFields) {
      f.dispose();
    }
    super.dispose();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().hashCode}';

  // ── B1: kelola tag ──
  void _addTag(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    final exists = _tags.any((t) => t.toLowerCase() == v.toLowerCase());
    setState(() {
      if (!exists) _tags.add(v);
      _tagInput.clear();
    });
  }

  void _removeTag(String t) => setState(() => _tags.remove(t));

  /// Commit tag yang masih ngambang di input (belum jadi chip) saat simpan.
  List<String> _commitTags() {
    final pending = _tagInput.text.trim();
    if (pending.isNotEmpty &&
        !_tags.any((t) => t.toLowerCase() == pending.toLowerCase())) {
      _tags.add(pending);
    }
    return _tags;
  }

  // ── B2: tipe entry & field tambahan ──
  void _onTypeChanged(EntryType? t) {
    if (t == null) return;
    setState(() {
      _type = t;
      // Untuk entry BARU yang field tambahannya masih kosong, isi saran field
      // sesuai tipe biar user tidak mulai dari nol.
      if (!_isEdit && _customFields.isEmpty) {
        for (final s in _suggestedFields(t)) {
          _customFields.add(_CustomFieldDraft(label: s.$1, secret: s.$2));
        }
      }
    });
  }

  /// Saran (label, rahasia?) field tambahan per tipe entry.
  List<(String, bool)> _suggestedFields(EntryType t) {
    switch (t) {
      case EntryType.card:
        return const [
          ('Nomor Kartu', true),
          ('Nama di Kartu', false),
          ('Berlaku Hingga (MM/YY)', false),
          ('CVV', true),
        ];
      case EntryType.bankAccount:
        return const [
          ('Nama Bank', false),
          ('Nomor Rekening', false),
          ('Atas Nama', false),
          ('PIN', true),
        ];
      case EntryType.identity:
        return const [
          ('Nomor Identitas (NIK)', false),
          ('Nama Lengkap', false),
          ('Tanggal Lahir', false),
          ('Alamat', false),
        ];
      case EntryType.wifi:
        return const [
          ('Nama Jaringan (SSID)', false),
          ('Kata Sandi WiFi', true),
          ('Tipe Keamanan', false),
        ];
      case EntryType.login:
      case EntryType.secureNote:
        return const [];
    }
  }

  void _addCustomField() =>
      setState(() => _customFields.add(_CustomFieldDraft()));

  void _removeCustomField(_CustomFieldDraft d) => setState(() {
        _customFields.remove(d);
        d.dispose();
      });

  /// Bangun daftar CustomField dari draft (skip baris yang benar-benar kosong).
  List<CustomField> _commitCustomFields() {
    final out = <CustomField>[];
    for (final d in _customFields) {
      final label = d.label.text.trim();
      final value = d.value.text;
      if (label.isEmpty && value.trim().isEmpty) continue;
      out.add(CustomField(
        label: label.isEmpty ? 'Field' : label,
        value: value,
        secret: d.secret,
      ));
    }
    return out;
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Judul wajib diisi.')));
      return;
    }
    final tags = _commitTags();
    if (_isEdit) {
      final e = widget.entry!
        ..title = _title.text.trim()
        ..username = _username.text.trim()
        ..password = _password.text
        ..url = _url.text.trim()
        ..notes = _notes.text
        ..totpSecret = _totp.text.trim()
        ..folder = _folder.text.trim()
        ..tags = tags
        ..favorite = _favorite
        ..type = _type
        ..customFields = _commitCustomFields();
      await widget.controller.updateEntry(e);
    } else {
      await widget.controller.addEntry(VaultEntry(
        id: _newId(),
        title: _title.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        url: _url.text.trim(),
        notes: _notes.text,
        totpSecret: _totp.text.trim(),
        folder: _folder.text.trim(),
        tags: tags,
        favorite: _favorite,
        type: _type,
        customFields: _commitCustomFields(),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus entry?'),
        content: const Text('Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.deleteEntry(widget.entry!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── B4: Generator password / passphrase ──
  Future<void> _openGenerator() async {
    final gen = PasswordGenerator();
    final s = widget.settings.settings;
    var usePassphrase = s.genUsePassphrase;
    var length = s.genLength.clamp(8, 40);
    var useUpper = s.genUpper;
    var useDigits = s.genDigits;
    var useSymbols = s.genSymbols;
    var phWords = s.genPhWords.clamp(3, 12);
    var sep = s.genPhSeparator;
    var capitalize = s.genPhCapitalize;
    var addNumber = s.genPhNumber;

    const separators = <String, String>{
      'Strip ( - )': '-',
      'Titik ( . )': '.',
      'Garis bawah ( _ )': '_',
      'Spasi': ' ',
      'Tanpa': '',
    };
    if (!separators.values.contains(sep)) sep = '-';

    String build() => usePassphrase
        ? gen.generatePassphrase(
            words: phWords,
            separator: sep,
            capitalize: capitalize,
            addNumber: addNumber,
          )
        : gen.generate(
            length: length,
            useUpper: useUpper,
            useDigits: useDigits,
            useSymbols: useSymbols,
          );

    var preview = build();

    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          void regen() => setLocal(() => preview = build());
          final bits = usePassphrase
              ? PasswordGenerator.passphraseEntropyBits(
                  words: phWords, addNumber: addNumber)
              : PasswordGenerator.randomEntropyBits(
                  length: length,
                  useUpper: useUpper,
                  useDigits: useDigits,
                  useSymbols: useSymbols,
                );
          final cs = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: const Text('Generator Password'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('Acak'),
                            icon: Icon(Icons.casino)),
                        ButtonSegment(
                            value: true,
                            label: Text('Passphrase'),
                            icon: Icon(Icons.menu_book_outlined)),
                      ],
                      selected: {usePassphrase},
                      onSelectionChanged: (sel) => setLocal(() {
                        usePassphrase = sel.first;
                        preview = build();
                      }),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        preview,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Entropi \u2248 ${bits.round()} bit \u00b7 ${_strengthWord(bits)}',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: regen,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Acak ulang'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (!usePassphrase) ...[
                      Text('Panjang: $length',
                          style:
                              Theme.of(dialogContext).textTheme.bodyMedium),
                      Slider(
                        min: 8,
                        max: 40,
                        divisions: 32,
                        value: length.toDouble(),
                        label: '$length',
                        onChanged: (v) => setLocal(() {
                          length = v.round();
                          preview = build();
                        }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Huruf besar (A-Z)'),
                        value: useUpper,
                        onChanged: (v) => setLocal(() {
                          useUpper = v;
                          preview = build();
                        }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Angka (0-9)'),
                        value: useDigits,
                        onChanged: (v) => setLocal(() {
                          useDigits = v;
                          preview = build();
                        }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Simbol (!@#...)'),
                        value: useSymbols,
                        onChanged: (v) => setLocal(() {
                          useSymbols = v;
                          preview = build();
                        }),
                      ),
                    ] else ...[
                      Text('Jumlah kata: $phWords',
                          style:
                              Theme.of(dialogContext).textTheme.bodyMedium),
                      Slider(
                        min: 3,
                        max: 12,
                        divisions: 9,
                        value: phWords.toDouble(),
                        label: '$phWords',
                        onChanged: (v) => setLocal(() {
                          phWords = v.round();
                          preview = build();
                        }),
                      ),
                      Text(
                        'Diambil acak dari kamus ${PasswordGenerator.wordlistSize} kata.',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Pemisah'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: sep,
                              items: [
                                for (final e in separators.entries)
                                  DropdownMenuItem(
                                      value: e.value, child: Text(e.key)),
                              ],
                              onChanged: (v) => setLocal(() {
                                sep = v ?? '-';
                                preview = build();
                              }),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Huruf awal kapital'),
                        value: capitalize,
                        onChanged: (v) => setLocal(() {
                          capitalize = v;
                          preview = build();
                        }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Sisipkan angka di akhir'),
                        value: addNumber,
                        onChanged: (v) => setLocal(() {
                          addNumber = v;
                          preview = build();
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, preview),
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      ),
    );

    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _password.text = picked;
        _obscure = false;
      });
      // Simpan preferensi terakhir biar jadi default generator berikutnya.
      widget.settings.update(s.copyWith(
        genUsePassphrase: usePassphrase,
        genLength: length,
        genUpper: useUpper,
        genDigits: useDigits,
        genSymbols: useSymbols,
        genPhWords: phWords,
        genPhSeparator: sep,
        genPhCapitalize: capitalize,
        genPhNumber: addNumber,
      ));
    }
  }

  /// Label kekuatan ringkas dari estimasi entropi (bit).
  String _strengthWord(double bits) {
    if (bits < 40) return 'Lemah';
    if (bits < 60) return 'Cukup';
    if (bits < 80) return 'Kuat';
    return 'Sangat kuat';
  }

  /// Indikator kekuatan password sederhana (panjang + ragam karakter).
  Widget _strengthMeter(String pw) {
    var classes = 0;
    if (pw.contains(RegExp(r'[a-z]'))) classes++;
    if (pw.contains(RegExp(r'[A-Z]'))) classes++;
    if (pw.contains(RegExp(r'[0-9]'))) classes++;
    if (pw.contains(RegExp(r'[^A-Za-z0-9]'))) classes++;
    var score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (pw.length >= 16) score++;
    if (classes >= 3) score++;
    if (score > 4) score = 4;
    const labels = ['Sangat lemah', 'Lemah', 'Cukup', 'Kuat', 'Sangat kuat'];
    const colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.orange,
      Colors.lightGreen,
      Colors.green,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (score + 1) / 5,
            minHeight: 6,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(colors[score]),
          ),
        ),
        const SizedBox(height: 4),
        Text('Kekuatan: ${labels[score]}',
            style: TextStyle(fontSize: 12, color: colors[score])),
      ],
    );
  }

  /// Satu baris editor custom field (label + nilai + toggle rahasia + hapus).
  Widget _customFieldRow(_CustomFieldDraft d) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            TextField(
              controller: d.label,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'mis. Nomor Kartu',
                isDense: true,
                border: InputBorder.none,
              ),
            ),
            TextField(
              controller: d.value,
              obscureText: d.secret,
              minLines: 1,
              maxLines: d.secret ? 1 : 3,
              decoration: const InputDecoration(
                labelText: 'Nilai',
                isDense: true,
                border: InputBorder.none,
              ),
            ),
            Row(
              children: [
                Icon(d.secret ? Icons.lock_outline : Icons.lock_open_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                const Text('Rahasia'),
                Switch(
                  value: d.secret,
                  onChanged: (v) => setState(() => d.secret = v),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  tooltip: 'Hapus field',
                  onPressed: () => _removeCustomField(d),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTotp = _totp.text.trim().isNotEmpty;
    final folders = widget.controller.allFolders;
    final tagSuggestions = widget.controller.allTags
        .where((t) => !_tags.any((x) => x.toLowerCase() == t.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Entry' : 'Tambah Entry'),
        actions: [
          IconButton(
            icon: Icon(_favorite ? Icons.star : Icons.star_border,
                color: _favorite ? Colors.amber : null),
            tooltip: _favorite ? 'Hapus dari favorit' : 'Tandai favorit',
            onPressed: () => setState(() => _favorite = !_favorite),
          ),
          if (_isEdit)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Judul *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          // ── B2: Tipe entry ──
          DropdownButtonFormField<EntryType>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'Tipe',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              for (final t in EntryType.values)
                DropdownMenuItem(
                  value: t,
                  child: Row(children: [
                    Icon(entryTypeIcon(t), size: 18),
                    const SizedBox(width: 10),
                    Text(t.label),
                  ]),
                ),
            ],
            onChanged: _onTypeChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
                labelText: 'Username / Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    icon: const Icon(Icons.casino),
                    tooltip: 'Generator password',
                    onPressed: _openGenerator,
                  ),
                ],
              ),
            ),
          ),
          if (_password.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _strengthMeter(_password.text),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
                labelText: 'URL', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          // ── B1: Folder / Kategori ──
          TextField(
            controller: _folder,
            decoration: const InputDecoration(
              labelText: 'Folder / Kategori',
              hintText: 'mis. Kerja, Pribadi, Bank',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          if (folders.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in folders)
                  ActionChip(
                    label: Text(f),
                    onPressed: () => setState(() => _folder.text = f),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // ── B1: Tag ──
          TextField(
            controller: _tagInput,
            textInputAction: TextInputAction.done,
            onSubmitted: _addTag,
            decoration: InputDecoration(
              labelText: 'Tag',
              hintText: 'Ketik lalu Enter untuk menambah',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.label_outline),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Tambah tag',
                onPressed: () => _addTag(_tagInput.text),
              ),
            ),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in _tags)
                  InputChip(label: Text(t), onDeleted: () => _removeTag(t)),
              ],
            ),
          ],
          if (tagSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in tagSuggestions)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(t),
                    onPressed: () => _addTag(t),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(_favorite ? Icons.star : Icons.star_border,
                color: _favorite ? Colors.amber : null),
            title: const Text('Favorit'),
            subtitle: const Text('Tampil di bagian Favorit'),
            value: _favorite,
            onChanged: (v) => setState(() => _favorite = v),
          ),
          const SizedBox(height: 12),
          // ── Bagian TOTP / 2FA ──
          TextField(
            controller: _totp,
            onChanged: (_) => setState(() {}), // refresh preview
            decoration: const InputDecoration(
              labelText: 'Secret 2FA (base32, opsional)',
              hintText: 'mis. JBSWY3DPEHPK3PXP',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.shield_outlined),
            ),
          ),
          if (hasTotp) ...[
            const SizedBox(height: 8),
            TotpCodeTile(secret: _totp.text.trim()),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Catatan', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          // ── B2: Field Tambahan ──
          Row(
            children: [
              Icon(Icons.list_alt_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Field Tambahan',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Simpan data lain seperti nomor kartu, PIN, atau pertanyaan keamanan. '
            'Aktifkan "Rahasia" untuk menyembunyikan & auto-hapus clipboard saat disalin.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final d in _customFields) _customFieldRow(d),
          OutlinedButton.icon(
            onPressed: _addCustomField,
            icon: const Icon(Icons.add),
            label: const Text('Tambah Field'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Simpan'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draft mutable untuk satu custom field di form (punya controller sendiri).
class _CustomFieldDraft {
  final TextEditingController label;
  final TextEditingController value;
  bool secret;
  _CustomFieldDraft(
      {String label = '', String value = '', this.secret = false})
      : label = TextEditingController(text: label),
        value = TextEditingController(text: value);
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

/// Ikon Material untuk tiap tipe entry. Dipakai oleh form ini & home_screen
/// (home_screen meng-import file ini, jadi cukup didefinisikan sekali di sini).
IconData entryTypeIcon(EntryType t) {
  switch (t) {
    case EntryType.login:
      return Icons.vpn_key_outlined;
    case EntryType.card:
      return Icons.credit_card;
    case EntryType.bankAccount:
      return Icons.account_balance_outlined;
    case EntryType.identity:
      return Icons.badge_outlined;
    case EntryType.wifi:
      return Icons.wifi;
    case EntryType.secureNote:
      return Icons.sticky_note_2_outlined;
  }
}
