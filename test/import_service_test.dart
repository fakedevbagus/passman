import 'package:flutter_test/flutter_test.dart';
import 'package:passman/models/vault_entry.dart';
import 'package:passman/services/import_service.dart';

void main() {
  group('detectFormat', () {
    test('Chrome CSV', () {
      const csv = 'name,url,username,password\nGitHub,https://github.com,me,secret';
      expect(ImportService.detectFormat(csv), ImportFormat.chromeCsv);
    });

    test('Bitwarden CSV (kolom login_password)', () {
      const csv = 'folder,favorite,type,name,login_uri,login_username,login_password,login_totp\n,,login,GitHub,https://github.com,me,secret,';
      expect(ImportService.detectFormat(csv), ImportFormat.bitwardenCsv);
    });

    test('LastPass CSV (grouping + extra)', () {
      const csv = 'url,username,password,extra,name,grouping,fav\nhttps://x.com,me,secret,,X,Work,0';
      expect(ImportService.detectFormat(csv), ImportFormat.lastpassCsv);
    });

    test('1Password CSV (kolom otpauth)', () {
      const csv = 'title,url,username,password,otpauth,notes\nX,https://x.com,me,secret,,';
      expect(ImportService.detectFormat(csv), ImportFormat.onePasswordCsv);
    });

    test('KeePass CSV ("Login Name")', () {
      const csv = 'Account,Login Name,Password,Web Site,Comments\nX,me,secret,https://x.com,';
      expect(ImportService.detectFormat(csv), ImportFormat.keepassCsv);
    });

    test('JSON -> Bitwarden JSON', () {
      const json = '{"items":[]}';
      expect(ImportService.detectFormat(json), ImportFormat.bitwardenJson);
    });
  });

  group('parse Chrome / generic CSV', () {
    test('2 baris -> 2 entry, kolom termap', () {
      const csv =
          'name,url,username,password\nGitHub,https://github.com,octo,hunter2\nMail,https://mail.com,bob,pw';
      final res = ImportService.parse(csv);
      expect(res.format, ImportFormat.chromeCsv);
      expect(res.count, 2);
      final gh = res.entries.firstWhere((e) => e.title == 'GitHub');
      expect(gh.username, 'octo');
      expect(gh.password, 'hunter2');
      expect(gh.url, 'https://github.com');
    });

    test('baris kosong dilewati', () {
      const csv = 'name,url,username,password\nA,,,\n,,,\nB,,,';
      final res = ImportService.parse(csv);
      expect(res.count, 2);
    });
  });

  group('parse Bitwarden JSON', () {
    test('item login termap lengkap', () {
      const json = '''
{"folders":[{"id":"f1","name":"Kerja"}],
 "items":[{"type":1,"name":"GitHub","folderId":"f1","favorite":true,
   "login":{"username":"octo","password":"hunter2",
     "uris":[{"uri":"https://github.com"}]}}]}''';
      final res = ImportService.parse(json);
      expect(res.format, ImportFormat.bitwardenJson);
      expect(res.count, 1);
      final e = res.entries.first;
      expect(e.title, 'GitHub');
      expect(e.username, 'octo');
      expect(e.password, 'hunter2');
      expect(e.url, 'https://github.com');
      expect(e.folder, 'Kerja');
      expect(e.favorite, isTrue);
      expect(e.type, EntryType.login);
    });
  });

  group('error handling', () {
    test('file kosong -> ImportException', () {
      expect(() => ImportService.parse('   '), throwsA(isA<ImportException>()));
    });

    test('JSON tanpa items -> ImportException', () {
      expect(() => ImportService.parse('{"foo":1}'),
          throwsA(isA<ImportException>()));
    });
  });
}
