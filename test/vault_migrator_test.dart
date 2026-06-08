import 'package:flutter_test/flutter_test.dart';
import 'package:passman/models/vault_entry.dart';
import 'package:passman/services/vault_migrator.dart';

Map<String, dynamic> _legacyEntry(String id, String title) => {
      'id': id,
      'title': title,
      'username': 'u_$id',
      'password': 'p_$id',
      'createdAt': '2024-01-01T00:00:00.000',
      'updatedAt': '2024-01-01T00:00:00.000',
    };

void main() {
  group('migrate', () {
    test('v0 (List polos legacy) -> currentVersion, didMigrate true', () {
      final legacy = [_legacyEntry('1', 'A'), _legacyEntry('2', 'B')];
      final (data, didMigrate) = VaultSchema.migrate(legacy);
      expect(didMigrate, isTrue);
      expect(data['schemaVersion'], VaultSchema.currentVersion);

      final entries = VaultSchema.decodeEntries(data);
      expect(entries.length, 2);
      // Default field baru terisi aman.
      expect(entries.first.folder, '');
      expect(entries.first.tags, isEmpty);
      expect(entries.first.favorite, isFalse);
      expect(entries.first.type, EntryType.login);
      expect(entries.first.customFields, isEmpty);
      // Field lama tetap utuh.
      expect(entries.first.username, 'u_1');
    });

    test('envelope sudah currentVersion -> didMigrate false', () {
      final env = {
        'schemaVersion': VaultSchema.currentVersion,
        'entries': [_legacyEntry('1', 'A')],
      };
      final (data, didMigrate) = VaultSchema.migrate(env);
      expect(didMigrate, isFalse);
      expect(data['schemaVersion'], VaultSchema.currentVersion);
    });

    test('versi lebih baru dari aplikasi -> SchemaTooNewException', () {
      final env = {'schemaVersion': 999, 'entries': <dynamic>[]};
      expect(() => VaultSchema.migrate(env),
          throwsA(isA<SchemaTooNewException>()));
    });

    test('struktur tak dikenal -> FormatException', () {
      expect(() => VaultSchema.migrate(42), throwsA(isA<FormatException>()));
      expect(() => VaultSchema.migrate({'foo': 'bar'}),
          throwsA(isA<FormatException>()));
    });
  });

  group('encode / round-trip', () {
    test('encode memakai currentVersion', () {
      final e = VaultEntry(id: '1', title: 'A');
      final env = VaultSchema.encode([e]);
      expect(env['schemaVersion'], VaultSchema.currentVersion);
      expect((env['entries'] as List).length, 1);
    });

    test('migrate(encode(x)) stabil & tanpa migrasi', () {
      final e = VaultEntry(id: '1', title: 'A', folder: 'Kerja');
      final (data, didMigrate) = VaultSchema.migrate(VaultSchema.encode([e]));
      expect(didMigrate, isFalse);
      final back = VaultSchema.decodeEntries(data);
      expect(back.single.title, 'A');
      expect(back.single.folder, 'Kerja');
    });
  });
}
