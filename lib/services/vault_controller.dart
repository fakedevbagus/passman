import 'package:flutter/foundation.dart';
import '../models/vault_entry.dart';
import 'vault_storage.dart';
import 'breach_service.dart';

class VaultController extends ChangeNotifier {
  final VaultStorage _storage = VaultStorage();

  SecretKeyHolder? _keyHolder;
  List<VaultEntry> _entries = [];
  String _query = '';

  // B3: cek kebocoran (HIBP). Semua status di bawah ini in-memory saja dan
  // dihapus saat lock() — status kebocoran TIDAK PERNAH ditulis ke disk.
  final BreachService _breach = BreachService();
  final Map<String, int> _breachCounts = {}; // id -> jumlah temuan (0 = aman)
  final Set<String> _breachInFlight = {}; // id yang sedang dicek
  bool _scanningBreaches = false;
  DateTime? _lastBreachScan;

  bool get isUnlocked => _keyHolder != null;
  String get query => _query;

  // Proteksi brute-force (in-memory; reset saat app ditutup)
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  Duration? get lockoutRemaining {
    if (_lockedUntil == null) return null;
    final diff = _lockedUntil!.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  List<VaultEntry> get entries {
    if (_query.isEmpty) return List.unmodifiable(_entries);
    final q = _query.toLowerCase();
    return _entries
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.url.toLowerCase().contains(q) ||
            e.folder.toLowerCase().contains(q) ||
            e.tags.any((t) => t.toLowerCase().contains(q)) ||
            e.customFields.any((f) =>
                f.label.toLowerCase().contains(q) ||
                (!f.secret && f.value.toLowerCase().contains(q))))
        .toList();
  }

  /// Semua entry (tanpa filter pencarian) — dipakai dashboard kesehatan & export.
  List<VaultEntry> get allEntries => List.unmodifiable(_entries);

  /// B1: semua folder unik (non-kosong), urut alfabet — untuk nav sidebar & form.
  List<String> get allFolders {
    final set = <String>{};
    for (final e in _entries) {
      final f = e.folder.trim();
      if (f.isNotEmpty) set.add(f);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// B1: semua tag unik, urut alfabet — untuk form & filter.
  List<String> get allTags {
    final set = <String>{};
    for (final e in _entries) {
      for (final t in e.tags) {
        final v = t.trim();
        if (v.isNotEmpty) set.add(v);
      }
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<bool> vaultExists() => _storage.vaultExists();

  Future<void> setupMaster(String masterPassword) async {
    _keyHolder = await _storage.createVault(masterPassword: masterPassword);
    _entries = [];
    notifyListeners();
  }

  /// Buka vault. Hanya password salah yang dihitung sebagai percobaan gagal;
  /// error lain (korup / IO / belum dibuat) dilempar apa adanya tanpa
  /// menambah hitungan brute-force.
  Future<void> unlock(String masterPassword) async {
    final remaining = lockoutRemaining;
    if (remaining != null) {
      throw 'Terkunci. Coba lagi dalam ${remaining.inSeconds} detik.';
    }
    try {
      final (holder, entries) = await _storage.unlock(masterPassword);
      _keyHolder = holder;
      _entries = entries;
      _failedAttempts = 0;
      _lockedUntil = null;
      notifyListeners();
    } on WrongPasswordException {
      _failedAttempts++;
      if (_failedAttempts >= 5) {
        _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _failedAttempts = 0;
        throw 'Terlalu banyak percobaan gagal. Terkunci 30 detik.';
      }
      throw 'Master password salah. Sisa ${5 - _failedAttempts} percobaan.';
    } on VaultException catch (e) {
      // Korup / IO / belum dibuat → bukan salah password, jangan dihitung.
      throw e.toString();
    }
  }

  void lock() {
    _keyHolder = null;
    _entries = [];
    _query = '';
    // Privasi: jangan simpan status kebocoran setelah terkunci.
    _breachCounts.clear();
    _breachInFlight.clear();
    _lastBreachScan = null;
    _breach.clearCache();
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  /// Cek apakah master password benar (tanpa mengubah sesi aktif).
  Future<bool> verifyPassword(String pw) async {
    try {
      await _storage.unlock(pw);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ganti master password: re-enkripsi seluruh entry dengan kunci baru.
  Future<void> changeMasterPassword(String newPassword) async {
    final current = List<VaultEntry>.from(_entries);
    await setupMaster(newPassword); // buat salt + kunci baru
    _entries = current; // kembalikan entry yang ada
    await _persist(); // simpan ulang dengan kunci baru
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_keyHolder == null) return;
    await _storage.save(keyHolder: _keyHolder!, entries: _entries);
  }

  Future<void> addEntry(VaultEntry entry) async {
    _entries.add(entry);
    await _persist();
    notifyListeners();
  }

  /// Tambah banyak entry sekaligus (mis. hasil import CSV) — 1x simpan saja.
  Future<void> addEntries(List<VaultEntry> newEntries) async {
    if (newEntries.isEmpty) return;
    _entries.addAll(newEntries);
    await _persist();
    notifyListeners();
  }

  Future<void> updateEntry(VaultEntry entry) async {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      entry.updatedAt = DateTime.now();
      _entries[i] = entry;
      _breachCounts.remove(entry.id); // password mungkin berubah -> cek ulang
      await _persist();
      notifyListeners();
    }
  }

  /// B1: toggle status favorit sebuah entry & simpan.
  Future<void> toggleFavorite(String id) async {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final e = _entries[i];
    e.favorite = !e.favorite;
    e.updatedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  // ================== B3: cek kebocoran (HIBP) ==================

  bool get isScanningBreaches => _scanningBreaches;
  DateTime? get lastBreachScan => _lastBreachScan;

  /// True kalau entry [id] sudah pernah dicek pada sesi ini.
  bool isBreachChecked(String id) => _breachCounts.containsKey(id);

  /// True kalau entry [id] sedang dalam proses pengecekan.
  bool isCheckingBreach(String id) => _breachInFlight.contains(id);

  /// Jumlah temuan kebocoran untuk entry [id] (0 = aman / belum dicek).
  int breachCountFor(String id) => _breachCounts[id] ?? 0;

  /// Jumlah entry (yang sudah dicek) yang ketahuan bocor.
  int get breachedCount => _breachCounts.values.where((c) => c > 0).length;

  /// Cek satu entry ke HIBP. Melempar [BreachCheckException] kalau gagal
  /// (mis. tidak ada internet) supaya UI bisa menampilkan pesannya.
  Future<void> checkEntryBreach(String id) async {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final pw = _entries[i].password;
    if (pw.isEmpty) {
      _breachCounts[id] = 0;
      notifyListeners();
      return;
    }
    if (_breachInFlight.contains(id)) return;
    _breachInFlight.add(id);
    notifyListeners();
    try {
      final count = await _breach.pwnedCount(pw);
      _breachCounts[id] = count;
    } catch (_) {
      _breachInFlight.remove(id);
      notifyListeners();
      rethrow;
    }
    _breachInFlight.remove(id);
    notifyListeners();
  }

  /// Scan seluruh entry sekaligus (untuk dashboard keamanan). Password yang
  /// identik hanya dicek satu kali. Mengembalikan ringkasan hasil.
  Future<({int total, int breached, int failed})> scanAllBreaches() async {
    if (_scanningBreaches) return (total: 0, breached: 0, failed: 0);
    _scanningBreaches = true;
    notifyListeners();
    var breached = 0;
    var failed = 0;
    // Kelompokkan id berdasarkan password unik (yang non-kosong).
    final byPassword = <String, List<String>>{};
    for (final e in _entries) {
      if (e.password.isEmpty) {
        _breachCounts[e.id] = 0;
        continue;
      }
      byPassword.putIfAbsent(e.password, () => []).add(e.id);
    }
    try {
      for (final group in byPassword.entries) {
        int count;
        try {
          count = await _breach.pwnedCount(group.key);
        } catch (_) {
          failed++;
          continue; // biarkan id ini berstatus "belum dicek"
        }
        for (final id in group.value) {
          _breachCounts[id] = count;
        }
        if (count > 0) breached += group.value.length;
      }
    } finally {
      _scanningBreaches = false;
      _lastBreachScan = DateTime.now();
      notifyListeners();
    }
    return (total: byPassword.length, breached: breached, failed: failed);
  }

  Future<void> deleteEntry(String id) async {
    _entries.removeWhere((e) => e.id == id);
    _breachCounts.remove(id);
    _breachInFlight.remove(id);
    await _persist();
    notifyListeners();
  }
}
