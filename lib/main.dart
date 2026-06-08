import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/vault_controller.dart';
import 'services/settings_service.dart';
import 'services/theme_controller.dart';
import 'services/window_service.dart';
import 'screens/lock_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsController.load();

  // Muat pilihan tema (System/Light/Dark) yang tersimpan.
  final themeController = ThemeController();
  await themeController.load();

  // W3+ : setup launch-at-startup (Windows). Saat di-enable, Passman akan
  // dijalankan dengan argumen --hidden agar langsung ngumpet ke tray.
  final packageInfo = await PackageInfo.fromPlatform();
  launchAtStartup.setup(
    appName: packageInfo.appName,
    appPath: Platform.resolvedExecutable,
    args: ['--hidden'],
  );

  // W3+ : setup window
  final startHidden = args.contains('--hidden');
  await windowManager.ensureInitialized();
  final bounds = await WindowService.load();
  final options = WindowOptions(
    size: Size(bounds.width, bounds.height),
    minimumSize: const Size(420, 560),
    title: 'Passman',
    center: bounds.x == null || bounds.y == null,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (bounds.x != null && bounds.y != null) {
      await windowManager.setPosition(Offset(bounds.x!, bounds.y!));
    }
    await windowManager.setPreventClose(true);
    if (startHidden) {
      // Dibuka otomatis saat startup → langsung sembunyi ke tray.
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(PassmanApp(settings: settings, themeController: themeController));
}

class PassmanApp extends StatefulWidget {
  final SettingsController settings;
  final ThemeController themeController;
  const PassmanApp({
    super.key,
    required this.settings,
    required this.themeController,
  });
  @override
  State<PassmanApp> createState() => _PassmanAppState();
}

class _PassmanAppState extends State<PassmanApp>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  final controller = VaultController();
  Timer? _idleTimer;
  Timer? _saveBoundsTimer;
  DateTime _lastActivity = DateTime.now();

  Future<void> _initTray() async {
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('Passman');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Buka Passman'),
      MenuItem.separator(),
      MenuItem(key: 'lock', label: 'Kunci sekarang'),
      MenuItem(key: 'exit', label: 'Keluar'),
    ]));
  }

  // Klik kiri ikon tray → buka window
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  // Klik kanan ikon tray → tampilkan menu
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'lock':
        if (controller.isUnlocked) controller.lock();
        break;
      case 'exit':
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        break;
    }
  }

  // Tombol X → sembunyikan ke tray, bukan keluar
  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowResized() => _scheduleSaveBounds();
  @override
  void onWindowMoved() => _scheduleSaveBounds();

  void _scheduleSaveBounds() {
    _saveBoundsTimer?.cancel();
    _saveBoundsTimer = Timer(const Duration(milliseconds: 500), () async {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      await WindowService.save(WindowBounds(
        width: size.width,
        height: size.height,
        x: pos.dx,
        y: pos.dy,
      ));
    });
  }

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _initTray();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onVaultStateChange);
    widget.settings.addListener(_restartIdleTimer);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _saveBoundsTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    widget.settings.removeListener(_restartIdleTimer);
    controller.removeListener(_onVaultStateChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onVaultStateChange() => _restartIdleTimer();

  /// (Re)start timer idle. Hanya aktif saat vault terbuka & durasi > 0.
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (!controller.isUnlocked) return;
    final mins = widget.settings.settings.autoLockMinutes;
    if (mins <= 0) return; // auto-lock idle nonaktif
    _idleTimer = Timer(Duration(minutes: mins), () {
      if (controller.isUnlocked) controller.lock();
    });
  }

  /// Dipanggil tiap ada aktivitas pointer/keyboard (di-throttle 5 detik).
  void _onUserActivity() {
    if (!controller.isUnlocked) return;
    final now = DateTime.now();
    if (now.difference(_lastActivity) < const Duration(seconds: 5)) return;
    _lastActivity = now;
    _restartIdleTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // AUTO-LOCK: kunci otomatis saat app ke background / disembunyikan.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeController,
      builder: (context, _) => MaterialApp(
        title: 'Passman',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.themeController.mode,
        home: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, __) {
            _onUserActivity();
            return KeyEventResult.ignored;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _onUserActivity(),
            onPointerMove: (_) => _onUserActivity(),
            onPointerSignal: (_) => _onUserActivity(),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.isUnlocked
                  ? HomeScreen(
                      controller: controller,
                      settings: widget.settings,
                      themeController: widget.themeController,
                    )
                  : LockScreen(controller: controller),
            ),
          ),
        ),
      ),
    );
  }
}
