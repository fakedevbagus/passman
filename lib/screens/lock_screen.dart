import 'package:flutter/material.dart';
import '../services/vault_controller.dart';

class LockScreen extends StatefulWidget {
  final VaultController controller;
  const LockScreen({super.key, required this.controller});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool? _vaultExists;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final exists = await widget.controller.vaultExists();
    if (!mounted) return;
    setState(() => _vaultExists = exists);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (_vaultExists == false) {
        if (pw.length < 8) throw 'Master password minimal 8 karakter.';
        if (pw != _confirm.text) throw 'Konfirmasi password tidak cocok.';
        await widget.controller.setupMaster(pw);
      } else {
        await widget.controller.unlock(pw);
      }
    } catch (e) {
      setState(() {
        if (_vaultExists == false) {
          _error = e.toString();
        } else if (e is String) {
          _error = e; // pesan lockout
        } else {
          _error = 'Master password salah.';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_vaultExists == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isSetup = _vaultExists == false;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 64),
                const SizedBox(height: 16),
                Text(
                  isSetup ? 'Buat Master Password' : 'Buka Passman',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  isSetup
                      ? 'Master password mengenkripsi seluruh vault. Jika lupa, data TIDAK bisa dipulihkan.'
                      : 'Masukkan master password kamu.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: true,
                  onSubmitted: (_) => isSetup ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Master password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (isSetup) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Konfirmasi password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isSetup ? 'Buat Vault' : 'Buka'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}