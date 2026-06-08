; ============================================================================
;  Passman - Inno Setup script
;  Bikin installer Windows (PassmanSetup.exe) dari hasil build Flutter.
;
;  CARA PAKAI:
;   1. Install Inno Setup 6:  https://jrsoftware.org/isdl.php
;   2. Build release Flutter:  flutter build windows --release
;   3. Buka file .iss ini di Inno Setup Compiler, lalu klik Build (F9),
;      ATAU lewat CLI:  iscc passman.iss
;   4. Hasil: installer\Output\PassmanSetup-x.y.z.exe
;   5. Upload .exe itu sebagai aset di GitHub Release (tag vX.Y.Z).
;
;  GANTI bagian yang ditandai TODO sesuai punya kamu.
; ============================================================================

#define MyAppName "Passman"
; TODO(gxkuat): naikkan versi ini tiap rilis (samakan dgn pubspec & tag GitHub).
#define MyAppVersion "1.0.0"
#define MyAppPublisher "gxkuat brow"
#define MyAppURL "https://github.com/fakedevbagus/passman"
#define MyAppExeName "passman.exe"

; Folder hasil build Flutter (relatif ke lokasi file .iss ini, yaitu installer\).
; Default Flutter: build\windows\x64\runner\Release
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId unik & TETAP selama-lamanya (jangan diubah antar versi) -> dipakai
; Windows utk mengenali "upgrade vs install baru". GUID di bawah khusus Passman.
AppId={{8F2A4C7E-1B3D-4E9A-9C21-0A1B2C3D4E5F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Output installer
OutputDir=Output
OutputBaseFilename=PassmanSetup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Passman 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Boleh install per-user tanpa admin; pindah ke {autopf} (Program Files) butuh admin.
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Salin SELURUH isi folder Release (exe + flutter_windows.dll + data\ + plugin DLL).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Tawarkan jalankan app setelah install selesai.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Bersihkan sisa folder app saat uninstall (data vault ada di %APPDATA%, TIDAK dihapus).
Type: filesandordirs; Name: "{app}"
