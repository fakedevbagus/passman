import 'dart:math';

import 'passphrase_words.dart';

/// Generator password & passphrase. Selalu pakai [Random.secure] (CSPRNG).
class PasswordGenerator {
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _digits = '0123456789';
  static const _symbols = '!@#\$%^&*()-_=+[]{}';

  final _rnd = Random.secure();

  /// Password acak berbasis karakter (perilaku lama, tidak berubah).
  String generate({
    int length = 16,
    bool useUpper = true,
    bool useDigits = true,
    bool useSymbols = true,
  }) {
    var pool = _lower;
    if (useUpper) pool += _upper;
    if (useDigits) pool += _digits;
    if (useSymbols) pool += _symbols;
    return List.generate(
      length,
      (_) => pool[_rnd.nextInt(pool.length)],
    ).join();
  }

  /// Batas wajar jumlah kata passphrase.
  static const int minWords = 3;
  static const int maxWords = 12;

  /// Passphrase gaya diceware: rangkai [words] kata acak dari [kPassphraseWords]
  /// dipisah [separator]. Opsi [capitalize] (Huruf Awal) & [addNumber]
  /// (sisipkan satu angka acak di akhir).
  ///
  /// Contoh: `Kuda-Benar-Baterai-Staples-7`.
  String generatePassphrase({
    int words = 5,
    String separator = '-',
    bool capitalize = true,
    bool addNumber = true,
  }) {
    final count = words.clamp(minWords, maxWords);
    final picked = <String>[];
    for (var i = 0; i < count; i++) {
      var w = kPassphraseWords[_rnd.nextInt(kPassphraseWords.length)];
      if (capitalize && w.isNotEmpty) {
        w = w[0].toUpperCase() + w.substring(1);
      }
      picked.add(w);
    }
    var out = picked.join(separator);
    if (addNumber) {
      out += '$separator${_rnd.nextInt(10)}';
    }
    return out;
  }

  /// Estimasi entropi (bit) password acak karakter dengan opsi tertentu.
  static double randomEntropyBits({
    required int length,
    bool useUpper = true,
    bool useDigits = true,
    bool useSymbols = true,
  }) {
    var poolSize = 26; // huruf kecil
    if (useUpper) poolSize += 26;
    if (useDigits) poolSize += 10;
    if (useSymbols) poolSize += _symbols.length;
    if (poolSize <= 1 || length <= 0) return 0;
    return length * (log(poolSize) / log(2));
  }

  /// Estimasi entropi (bit) passphrase: log2(jumlah_kata) * N (+ angka).
  static double passphraseEntropyBits({
    required int words,
    bool addNumber = true,
  }) {
    final count = words.clamp(minWords, maxWords);
    final perWord = log(kPassphraseWords.length) / log(2);
    var bits = perWord * count;
    if (addNumber) bits += log(10) / log(2);
    return bits;
  }

  /// Jumlah kata dalam kamus passphrase (utk ditampilkan di UI).
  static int get wordlistSize => kPassphraseWords.length;
}
