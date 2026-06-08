import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passman/services/crypto_service.dart';

/// Unit test untuk lapisan kriptografi Passman:
/// Argon2id (derive key), AES-256-GCM (encrypt/decrypt), salt/nonce, integritas.
void main() {
  final crypto = CryptoService();
  const password = 'rahasia-super-kuat-123';

  group('newSalt()', () {
    test('panjang 16 byte', () {
      expect(crypto.newSalt().length, 16);
    });

    test('acak — dua salt berbeda', () {
      expect(crypto.newSalt(), isNot(equals(crypto.newSalt())));
    });
  });

  group('deriveKey() — Argon2id', () {
    test('deterministik: password + salt sama => key sama', () async {
      final salt = crypto.newSalt();
      final k1 = await crypto.deriveKey(masterPassword: password, salt: salt);
      final k2 = await crypto.deriveKey(masterPassword: password, salt: salt);
      expect(await k1.extractBytes(), equals(await k2.extractBytes()));
    });

    test('menghasilkan kunci 256-bit (32 byte)', () async {
      final k = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      expect((await k.extractBytes()).length, 32);
    });

    test('salt berbeda => key berbeda', () async {
      final k1 = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      final k2 = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      expect(await k1.extractBytes(),
          isNot(equals(await k2.extractBytes())));
    });

    test('password berbeda (salt sama) => key berbeda', () async {
      final salt = crypto.newSalt();
      final k1 = await crypto.deriveKey(masterPassword: password, salt: salt);
      final k2 =
          await crypto.deriveKey(masterPassword: 'password-lain', salt: salt);
      expect(await k1.extractBytes(),
          isNot(equals(await k2.extractBytes())));
    });
  });

  group('encrypt()/decrypt() — round-trip', () {
    late SecretKey key;

    setUp(() async {
      key = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
    });

    test('teks biasa', () async {
      const text = 'Hello Passman 123!';
      final blob = await crypto.encrypt(key: key, plaintext: text);
      expect(await crypto.decrypt(key: key, blob: blob), text);
    });

    test('string kosong', () async {
      final blob = await crypto.encrypt(key: key, plaintext: '');
      expect(await crypto.decrypt(key: key, blob: blob), '');
    });

    test('unicode & emoji', () async {
      const text = 'Sandiñ 🔐 こんにちは €ä';
      final blob = await crypto.encrypt(key: key, plaintext: text);
      expect(await crypto.decrypt(key: key, blob: blob), text);
    });

    test('payload panjang (simulasi vault JSON)', () async {
      final text =
          List.generate(500, (i) => 'entry-$i:pass-$i').join(';');
      final blob = await crypto.encrypt(key: key, plaintext: text);
      expect(await crypto.decrypt(key: key, blob: blob), text);
    });
  });

  group('keamanan', () {
    test('nonce & ciphertext acak: enkripsi data sama 2x => berbeda',
        () async {
      final key = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      final b1 = await crypto.encrypt(key: key, plaintext: 'data sama');
      final b2 = await crypto.encrypt(key: key, plaintext: 'data sama');
      expect(b1.nonce, isNot(equals(b2.nonce)));
      expect(b1.cipherText, isNot(equals(b2.cipherText)));
    });

    test('password salah => dekripsi ditolak', () async {
      final salt = crypto.newSalt();
      final keyBenar =
          await crypto.deriveKey(masterPassword: password, salt: salt);
      final blob = await crypto.encrypt(key: keyBenar, plaintext: 'rahasia');
      final keySalah =
          await crypto.deriveKey(masterPassword: 'salah-banget', salt: salt);
      expect(
        () => crypto.decrypt(key: keySalah, blob: blob),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('ciphertext di-tamper => dekripsi ditolak', () async {
      final key = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      final blob = await crypto.encrypt(key: key, plaintext: 'jangan diubah');
      final tampered = EncryptedBlob(
        nonce: blob.nonce,
        cipherText: _flipFirstByte(blob.cipherText),
        mac: blob.mac,
      );
      expect(
        () => crypto.decrypt(key: key, blob: tampered),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('MAC di-tamper => dekripsi ditolak', () async {
      final key = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      final blob = await crypto.encrypt(key: key, plaintext: 'integritas');
      final tampered = EncryptedBlob(
        nonce: blob.nonce,
        cipherText: blob.cipherText,
        mac: _flipFirstByte(blob.mac),
      );
      expect(
        () => crypto.decrypt(key: key, blob: tampered),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('EncryptedBlob — serialisasi', () {
    test('toJson/fromJson round-trip + masih bisa didekripsi', () async {
      final key = await crypto.deriveKey(
          masterPassword: password, salt: crypto.newSalt());
      final blob = await crypto.encrypt(key: key, plaintext: 'serialize me');
      final restored = EncryptedBlob.fromJson(blob.toJson());
      expect(restored.nonce, equals(blob.nonce));
      expect(restored.cipherText, equals(blob.cipherText));
      expect(restored.mac, equals(blob.mac));
      expect(await crypto.decrypt(key: key, blob: restored), 'serialize me');
    });
  });
}

/// Balik (flip) byte pertama untuk mensimulasikan data yang dirusak.
List<int> _flipFirstByte(List<int> input) {
  final copy = List<int>.from(input);
  copy[0] = copy[0] ^ 0xFF;
  return copy;
}
