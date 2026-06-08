import '../models/vault_entry.dart';

enum HealthIssue { weak, reused, old }

class PasswordHealth {
  static const oldThresholdDays = 180;

  /// Password dianggap lemah jika < 12 karakter ATAU variasi karakter < 3 jenis.
  static bool isWeak(String pw) {
    if (pw.length < 12) return true;
    var classes = 0;
    if (RegExp(r'[a-z]').hasMatch(pw)) classes++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) classes++;
    if (RegExp(r'[0-9]').hasMatch(pw)) classes++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) classes++;
    return classes < 3;
  }

  /// Analisa semua entry → map id -> daftar masalah.
  static Map<String, List<HealthIssue>> analyze(List<VaultEntry> entries) {
    final counts = <String, int>{};
    for (final e in entries) {
      if (e.password.isEmpty) continue;
      counts[e.password] = (counts[e.password] ?? 0) + 1;
    }
    final now = DateTime.now();
    final result = <String, List<HealthIssue>>{};
    for (final e in entries) {
      final issues = <HealthIssue>[];
      if (e.password.isNotEmpty) {
        if (isWeak(e.password)) issues.add(HealthIssue.weak);
        if ((counts[e.password] ?? 0) > 1) issues.add(HealthIssue.reused);
        if (now.difference(e.updatedAt).inDays > oldThresholdDays) {
          issues.add(HealthIssue.old);
        }
      }
      result[e.id] = issues;
    }
    return result;
  }

  /// Skor 0–100: persentase entry tanpa masalah.
  static int score(List<VaultEntry> entries) {
    if (entries.isEmpty) return 100;
    final analysis = analyze(entries);
    final healthy = analysis.values.where((i) => i.isEmpty).length;
    return ((healthy / entries.length) * 100).round();
  }
}