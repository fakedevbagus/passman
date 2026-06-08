import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../utils/random_bytes.dart';

/// Hasil enkripsi yang siap disimpan ke disk.
class EncryptedBlob {
  final List<int> nonce;      // IV untuk AES-GCM (unik tiap enkripsi)
  final List<int> cipherText; // data terenkripsi
  final List<int> mac;        // tag autentikasi GCM

  EncryptedBlob({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
        'nonce': base64Encode(nonce),
        'cipherText': base64Encode(cipherText),
        'mac': base64Encode(mac),
      };

  factory EncryptedBlob.fromJson(Map<String, dynamic> json) => EncryptedBlob(
        nonce: base64Decode(json['nonce'] as String),
        cipherText: base64Decode(json['cipherText'] as String),
        mac: base64Decode(json['mac'] as String),
      );
}

class CryptoService {
  // Parameter Argon2id. Naikkan memory/iterations untuk lebih kuat
  // (tapi lebih lambat). 19 MB & 2 iterasi = titik awal wajar.
  static final Argon2id _kdf = Argon2id(
    memory: 19456, // dalam KiB (~19 MB)
    parallelism: 1,
    iterations: 2,
    hashLength: 32, // 256-bit key
  );

  final AesGcm _aes = AesGcm.with256bits();

  /// Buat salt acak baru (simpan bersama vault, tidak rahasia).
  List<int> newSalt() => secureRandomBytes(16);

  /// Turunkan kunci 256-bit dari master password + salt.
  Future<SecretKey> deriveKey({
    required String masterPassword,
    required List<int> salt,
  }) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: salt,
    );
  }

  /// Enkripsi string menjadi EncryptedBlob.
  Future<EncryptedBlob> encrypt({
    required SecretKey key,
    required String plaintext,
  }) async {
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return EncryptedBlob(
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  /// Dekripsi EncryptedBlob kembali menjadi string.
  /// Melempar error jika master password salah (MAC gagal).
  Future<String> decrypt({
    required SecretKey key,
    required EncryptedBlob blob,
  }) async {
    final box = SecretBox(
      blob.cipherText,
      nonce: blob.nonce,
      mac: Mac(blob.mac),
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }
}
