import 'package:flutter_test/flutter_test.dart';
import 'package:passman/models/vault_entry.dart';
import 'package:passman/services/settings_service.dart';

void main() {
  group('CustomField', () {
    test('round-trip JSON', () {
      final f = CustomField(label: 'PIN', value: '1234', secret: true);
      final back = CustomField.fromJson(f.toJson());
      expect(back.label, 'PIN');
      expect(back.value, '1234');
      expect(back.secret, isTrue);
    });

    test('fromJson toleran terhadap field hilang', () {
      final f = CustomField.fromJson(<String, dynamic>{});
      expect(f.label, '');
      expect(f.value, '');
      expect(f.secret, isFalse);
    });
  });

  group('EntryType', () {
    test('id == nama enum', () {
      expect(EntryType.bankAccount.id, 'bankAccount');
    });

    test('fromId tidak dikenal -> login', () {
      expect(EntryTypeMeta.fromId('ngawur'), EntryType.login);
      expect(EntryTypeMeta.fromId(null), EntryType.login);
    });

    test('fromId(id) bolak-balik konsisten', () {
      for (final t in EntryType.values) {
        expect(EntryTypeMeta.fromId(t.id), t);
      }
    });
  });

  group('VaultEntry serialisasi', () {
    test('round-trip lengkap', () {
      final e = VaultEntry(
        id: 'abc',
        title: 'GitHub',
        username: 'octo',
        password: 'hunter2',
        url: 'https://github.com',
        notes: 'catatan',
        totpSecret: 'JBSWY3DPEHPK3PXP',
        folder: 'Kerja',
        tags: ['dev', 'penting'],
        favorite: true,
        type: EntryType.login,
        customFields: [CustomField(label: 'PIN', value: '1234', secret: true)],
        createdAt: DateTime.parse('2024-01-01T00:00:00.000'),
        updatedAt: DateTime.parse('2024-02-02T00:00:00.000'),
      );
      final back = VaultEntry.fromJson(e.toJson());
      expect(back.id, 'abc');
      expect(back.title, 'GitHub');
      expect(back.username, 'octo');
      expect(back.password, 'hunter2');
      expect(back.url, 'https://github.com');
      expect(back.notes, 'catatan');
      expect(back.totpSecret, 'JBSWY3DPEHPK3PXP');
      expect(back.folder, 'Kerja');
      expect(back.tags, ['dev', 'penting']);
      expect(back.favorite, isTrue);
      expect(back.type, EntryType.login);
      expect(back.customFields.single.label, 'PIN');
      expect(back.customFields.single.secret, isTrue);
      expect(back.createdAt, DateTime.parse('2024-01-01T00:00:00.000'));
      expect(back.updatedAt, DateTime.parse('2024-02-02T00:00:00.000'));
    });

    test('fromJson data lama (tanpa field B1/B2) pakai default aman', () {
      final old = {
        'id': '1',
        'title': 'Lama',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
      };
      final e = VaultEntry.fromJson(old);
      expect(e.folder, '');
      expect(e.tags, isEmpty);
      expect(e.favorite, isFalse);
      expect(e.type, EntryType.login);
      expect(e.customFields, isEmpty);
    });
  });

  group('AppSettings', () {
    test('default value', () {
      const s = AppSettings();
      expect(s.autoLockMinutes, 5);
      expect(s.clipboardClearSeconds, 20);
      expect(s.genLength, 20);
      expect(s.genUpper, isTrue);
      expect(s.genUsePassphrase, isFalse);
      expect(s.genPhWords, 5);
      expect(s.genPhSeparator, '-');
      expect(s.genPhCapitalize, isTrue);
      expect(s.genPhNumber, isTrue);
    });

    test('copyWith hanya mengganti field tertentu', () {
      const s = AppSettings();
      final s2 = s.copyWith(genPhWords: 7, genUsePassphrase: true);
      expect(s2.genPhWords, 7);
      expect(s2.genUsePassphrase, isTrue);
      // sisanya tetap
      expect(s2.genLength, 20);
      expect(s2.autoLockMinutes, 5);
    });

    test('round-trip JSON', () {
      const s = AppSettings(
        autoLockMinutes: 2,
        clipboardClearSeconds: 30,
        genLength: 24,
        genSymbols: false,
        genUsePassphrase: true,
        genPhWords: 6,
        genPhSeparator: '.',
        genPhCapitalize: false,
        genPhNumber: false,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.autoLockMinutes, 2);
      expect(back.clipboardClearSeconds, 30);
      expect(back.genLength, 24);
      expect(back.genSymbols, isFalse);
      expect(back.genUsePassphrase, isTrue);
      expect(back.genPhWords, 6);
      expect(back.genPhSeparator, '.');
      expect(back.genPhCapitalize, isFalse);
      expect(back.genPhNumber, isFalse);
    });

    test('fromJson kompatibel mundur (JSON lama tanpa field passphrase)', () {
      final old = {
        'autoLockMinutes': 10,
        'clipboardClearSeconds': 20,
        'genLength': 16,
        'genUpper': true,
        'genDigits': true,
        'genSymbols': true,
      };
      final s = AppSettings.fromJson(old);
      expect(s.genLength, 16);
      // field passphrase baru pakai default.
      expect(s.genUsePassphrase, isFalse);
      expect(s.genPhWords, 5);
      expect(s.genPhSeparator, '-');
      expect(s.genPhCapitalize, isTrue);
      expect(s.genPhNumber, isTrue);
    });

    test('fromJson{} -> semua default', () {
      final s = AppSettings.fromJson(<String, dynamic>{});
      expect(s.autoLockMinutes, 5);
      expect(s.genLength, 20);
      expect(s.genPhWords, 5);
    });
  });
}
