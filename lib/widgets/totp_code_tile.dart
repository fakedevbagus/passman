import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/totp_service.dart';

class TotpCodeTile extends StatefulWidget {
  final String secret;
  const TotpCodeTile({super.key, required this.secret});
  @override
  State<TotpCodeTile> createState() => _TotpCodeTileState();
}

class _TotpCodeTileState extends State<TotpCodeTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh tiap detik untuk update kode & countdown.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = TotpService.currentCode(widget.secret);
    if (code == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Secret TOTP tidak valid',
            style: TextStyle(color: Colors.red)),
      );
    }
    final remaining = TotpService.secondsRemaining();
    final pretty = '${code.substring(0, 3)} ${code.substring(3)}';
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(value: remaining / 30, strokeWidth: 3),
              Text('$remaining', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        title: Text(pretty,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2)),
        subtitle: const Text('Kode 2FA'),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Salin kode',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kode 2FA disalin.')));
          },
        ),
      ),
    );
  }
}