import 'dart:math';

/// Menghasilkan byte acak yang aman secara kriptografis.
/// Dipakai untuk salt (Argon2id) dan keperluan acak lainnya.
List<int> secureRandomBytes(int length) {
  final rnd = Random.secure();
  return List<int>.generate(length, (_) => rnd.nextInt(256));
}