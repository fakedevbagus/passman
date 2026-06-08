import 'package:flutter_test/flutter_test.dart';
import 'package:passman/services/password_generator.dart';
import 'package:passman/services/passphrase_words.dart';

void main() {
  final gen = PasswordGenerator();

  group('generate (acak karakter)', () {
    test('panjang default 16', () {
      expect(gen.generate().length, 16);
    });

    test('panjang custom dipatuhi', () {
      for (final n in [8, 20, 40]) {
        expect(gen.generate(length: n).length, n);
      }
    });

    test('hanya huruf kecil saat semua kelas lain dimatikan', () {
      final pw = gen.generate(
        length: 200,
        useUpper: false,
        useDigits: false,
        useSymbols: false,
      );
      expect(RegExp(r'^[a-z]+$').hasMatch(pw), isTrue);
    });

    test('tanpa simbol: tidak ada karakter simbol', () {
      final pw = gen.generate(length: 200, useSymbols: false);
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(pw), isTrue);
    });

    test('tanpa angka: tidak ada digit', () {
      final pw = gen.generate(length: 200, useDigits: false, useSymbols: false);
      expect(RegExp(r'[0-9]').hasMatch(pw), isFalse);
    });
  });

  group('generatePassphrase', () {
    test('jumlah kata default 5 + 1 angka di akhir (sep "-")', () {
      final p = gen.generatePassphrase();
      final parts = p.split('-');
      expect(parts.length, 6); // 5 kata + 1 angka
      expect(RegExp(r'^[0-9]$').hasMatch(parts.last), isTrue);
    });

    test('tanpa angka: parts == jumlah kata', () {
      final p = gen.generatePassphrase(words: 4, addNumber: false);
      expect(p.split('-').length, 4);
    });

    test('separator custom dipakai', () {
      final p = gen.generatePassphrase(words: 3, separator: '.', addNumber: false);
      expect(p.split('.').length, 3);
      expect(p.contains('-'), isFalse);
    });

    test('capitalize: tiap kata diawali huruf besar', () {
      final p = gen.generatePassphrase(words: 5, addNumber: false, capitalize: true);
      for (final w in p.split('-')) {
        expect(w[0], w[0].toUpperCase());
      }
    });

    test('capitalize false: kata tetap huruf kecil', () {
      final p = gen.generatePassphrase(words: 5, addNumber: false, capitalize: false);
      expect(RegExp(r'^[a-z-]+$').hasMatch(p), isTrue);
    });

    test('jumlah kata di-clamp ke rentang [minWords, maxWords]', () {
      final tooMany = gen.generatePassphrase(words: 100, addNumber: false);
      expect(tooMany.split('-').length, PasswordGenerator.maxWords);
      final tooFew = gen.generatePassphrase(words: 1, addNumber: false);
      expect(tooFew.split('-').length, PasswordGenerator.minWords);
    });
  });

  group('estimasi entropi', () {
    test('randomEntropyBits hanya huruf kecil (pool 26)', () {
      // 10 * log2(26) ≈ 47.004
      final bits = PasswordGenerator.randomEntropyBits(
        length: 10,
        useUpper: false,
        useDigits: false,
        useSymbols: false,
      );
      expect(bits, closeTo(47.004, 0.1));
    });

    test('randomEntropyBits semua kelas (pool 80)', () {
      // 10 * log2(80) ≈ 63.219
      final bits = PasswordGenerator.randomEntropyBits(length: 10);
      expect(bits, closeTo(63.219, 0.2));
    });

    test('randomEntropyBits length 0 -> 0', () {
      expect(PasswordGenerator.randomEntropyBits(length: 0), 0);
    });

    test('passphraseEntropyBits naik ~3.32 bit saat addNumber', () {
      final without = PasswordGenerator.passphraseEntropyBits(words: 5, addNumber: false);
      final withNum = PasswordGenerator.passphraseEntropyBits(words: 5, addNumber: true);
      expect(withNum - without, closeTo(3.3219, 0.01));
    });

    test('passphraseEntropyBits 5 kata wajar (~50 bit)', () {
      final bits = PasswordGenerator.passphraseEntropyBits(words: 5, addNumber: false);
      expect(bits, greaterThan(45));
      expect(bits, lessThan(55));
    });
  });

  group('kamus passphrase', () {
    test('wordlistSize == panjang kPassphraseWords', () {
      expect(PasswordGenerator.wordlistSize, kPassphraseWords.length);
    });

    test('semua kata unik & huruf kecil', () {
      expect(kPassphraseWords.toSet().length, kPassphraseWords.length);
      expect(kPassphraseWords.every((w) => w == w.toLowerCase()), isTrue);
    });

    test('kamus cukup besar (>= 1000 kata)', () {
      expect(kPassphraseWords.length, greaterThanOrEqualTo(1000));
    });
  });
}
