import 'package:otp/otp.dart';

class TotpService {
  /// Hasilkan kode TOTP 6 digit dari secret base32.
  /// null kalau secret kosong / tidak valid.
  static String? currentCode(String secret) {
    final clean = secret.replaceAll(' ', '').toUpperCase();
    if (clean.isEmpty) return null;
    try {
      return OTP.generateTOTPCodeString(
        clean,
        DateTime.now().millisecondsSinceEpoch,
        interval: 30,
        length: 6,
        algorithm: Algorithm.SHA1,
        isGoogle: true, // kompatibel Google Authenticator
      );
    } catch (_) {
      return null;
    }
  }

  /// Sisa detik sebelum kode berganti (periode 30 detik).
  static int secondsRemaining() {
    final secInPeriod = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
    return 30 - secInPeriod;
  }
}