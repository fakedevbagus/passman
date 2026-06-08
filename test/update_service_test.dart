import 'package:flutter_test/flutter_test.dart';
import 'package:passman/services/update_service.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('patch lebih tinggi -> baru', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('minor lebih tinggi -> baru', () {
      expect(UpdateService.isNewer('1.1.0', '1.0.9'), isTrue);
    });

    test('mayor lebih tinggi -> baru', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('versi sama -> bukan baru', () {
      expect(UpdateService.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('lebih lama -> bukan baru', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('prefix "v" diabaikan', () {
      expect(UpdateService.isNewer('v1.2.0', '1.1.0'), isTrue);
      expect(UpdateService.isNewer('V1.0.0', 'v1.0.0'), isFalse);
    });

    test('build metadata setelah "+" diabaikan', () {
      expect(UpdateService.isNewer('1.0.0+5', '1.0.0+2'), isFalse);
      expect(UpdateService.isNewer('1.0.1+1', '1.0.0+9'), isTrue);
    });

    test('pre-release suffix diabaikan untuk perbandingan inti', () {
      expect(UpdateService.isNewer('1.2.0-beta', '1.1.0'), isTrue);
      expect(UpdateService.isNewer('1.0.0-beta', '1.0.0'), isFalse);
    });

    test('panjang segmen beda ditangani (1.2 vs 1.2.0)', () {
      expect(UpdateService.isNewer('1.2', '1.2.0'), isFalse);
      expect(UpdateService.isNewer('1.2.1', '1.2'), isTrue);
    });
  });
}
