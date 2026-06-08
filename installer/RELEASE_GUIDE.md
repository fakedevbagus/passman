# Passman — Panduan Rilis & Auto-Update (D/W6)

Dokumen ini menjelaskan alur lengkap dari build sampai user dapat update otomatis
lewat **GitHub Releases + Inno Setup**.

---

## 0. Sekali saja: siapkan repo & konfigurasi

1. Bikin repo GitHub (publik) untuk Passman, mis. `https://github.com/<username>/passman`.
2. Edit **`lib/services/update_service.dart`**:
   - `_owner` → username GitHub kamu.
   - `_repo`  → nama repo (default `passman`).
3. Edit **`installer/passman.iss`**:
   - `#define MyAppURL` → URL repo kamu.
   - (opsional) `AppId` GUID **jangan diubah lagi** setelah rilis pertama —
     itu yang bikin Windows mengenali "upgrade" vs "install baru".

> Catatan: `update_service.dart` pakai **GitHub API publik tanpa token**
> (rate limit 60 req/jam/IP — lebih dari cukup untuk cek manual).

---

## 1. Tiap mau rilis versi baru

### a. Naikkan versi
Di **`pubspec.yaml`**:
```yaml
version: 1.1.0+2   # format: <versi>+<build>
```
Di **`installer/passman.iss`**:
```
#define MyAppVersion "1.1.0"
```
Keduanya HARUS sama dengan tag GitHub (lihat langkah d).

### b. Build release Flutter
```powershell
cd E:\vscode\passman\passman
flutter build windows --release
```
Hasil ada di `build\windows\x64\runner\Release\`.

### c. Bikin installer (.exe) dengan Inno Setup
1. Install **Inno Setup 6**: https://jrsoftware.org/isdl.php
2. Kompilasi:
   - GUI: buka `installer\passman.iss` → klik **Build** (F9), **atau**
   - CLI: `iscc installer\passman.iss`
3. Output: `installer\Output\PassmanSetup-1.1.0.exe`

### d. Bikin GitHub Release
1. Buat tag versi: `v1.1.0` (awalan `v` aman, sudah ditangani kode).
2. Di halaman repo → **Releases** → **Draft a new release**.
3. Pilih tag `v1.1.0`, isi judul + catatan rilis (jadi "release notes" di app).
4. **Upload `PassmanSetup-1.1.0.exe` sebagai aset** rilis. WAJIB ada `.exe`,
   karena `UpdateService` mencari aset ber-ekstensi `.exe` (prioritas nama yang
   mengandung `setup`/`install`).
5. **Publish release**.

---

## 2. Alur auto-update di aplikasi

`lib/services/update_service.dart` menyediakan:

| Method | Fungsi |
|---|---|
| `checkForUpdate()` | Cek rilis terbaru; balikin `UpdateInfo?` (null = sudah terbaru). |
| `fetchLatest()` | Ambil metadata rilis terbaru apa adanya. |
| `downloadInstaller(info, onProgress:)` | Unduh `.exe` ke folder temp + callback progress. |
| `launchInstallerAndExit(file)` | Jalankan installer lalu `exit(0)` (biar file app bisa ditimpa). |
| `openReleasePage([url])` | Buka halaman rilis di browser (alternatif manual). |
| `UpdateService.isNewer(a, b)` | Bandingkan versi (static, sudah ada unit test). |

### Contoh wiring sederhana (mis. di Settings → tombol "Cek pembaruan")
```dart
final svc = UpdateService();
try {
  final info = await svc.checkForUpdate();
  if (info == null) {
    // Tampilkan: "Kamu sudah pakai versi terbaru."
  } else if (info.hasInstaller) {
    // Tampilkan dialog: info.version + info.releaseNotes
    // Kalau user setuju:
    final file = await svc.downloadInstaller(info, onProgress: (r, t) {
      // update progress bar: t > 0 ? r / t : null
    });
    await svc.launchInstallerAndExit(file); // app keluar, installer jalan
  } else {
    await svc.openReleasePage(info.htmlUrl); // fallback: buka di browser
  }
} on UpdateException catch (e) {
  // Tampilkan e.message ke user (mis. via SnackBar).
} finally {
  svc.dispose();
}
```

> Installer Inno Setup mengenali `AppId` yang sama → otomatis meng-upgrade
> instalasi lama di tempat yang sama. Data vault di `%APPDATA%` TIDAK tersentuh.

---

## 3. Verifikasi

- `flutter test` → termasuk `test/update_service_test.dart` (logika `isNewer`).
- Uji manual end-to-end: rilis versi lebih tinggi, jalankan app versi lama,
  panggil `checkForUpdate()` → harus mendeteksi & bisa unduh + pasang.

---

## Checklist rilis (ringkas)
- [ ] `pubspec.yaml` version dinaikkan
- [ ] `passman.iss` `MyAppVersion` disamakan
- [ ] `flutter build windows --release`
- [ ] `iscc installer\passman.iss` → `PassmanSetup-x.y.z.exe`
- [ ] GitHub Release tag `vx.y.z` + upload `.exe` + Publish
- [ ] Uji `checkForUpdate()` dari versi lama
