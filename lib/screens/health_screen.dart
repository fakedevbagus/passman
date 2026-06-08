import 'package:flutter/material.dart';
import '../services/vault_controller.dart';
import '../services/password_health.dart';
import 'entry_form_screen.dart';
import '../services/settings_service.dart';

class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key, required this.controller, required this.settings});
  final VaultController controller;
  final SettingsController settings;

  String _label(HealthIssue i) => switch (i) {
        HealthIssue.weak => 'Lemah',
        HealthIssue.reused => 'Dipakai ulang',
        HealthIssue.old => 'Sudah lama',
      };

  Color _color(HealthIssue i) => switch (i) {
        HealthIssue.weak => Colors.red,
        HealthIssue.reused => Colors.orange,
        HealthIssue.old => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kesehatan Password')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final entries = controller.allEntries;
          final analysis = PasswordHealth.analyze(entries);
          final score = PasswordHealth.score(entries);
          final problems =
              entries.where((e) => (analysis[e.id] ?? []).isNotEmpty).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('$score',
                        style: Theme.of(context).textTheme.displayMedium),
                    const Text('Skor keamanan'),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                          value: score / 100, minHeight: 8),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: problems.isEmpty
                    ? const Center(child: Text('Semua password sehat! 🎉'))
                    : ListView.builder(
                        itemCount: problems.length,
                        itemBuilder: (context, i) {
                          final e = problems[i];
                          final issues = analysis[e.id]!;
                          return ListTile(
                            title: Text(e.title),
                            subtitle: Wrap(
                              spacing: 6,
                              children: issues
                                  .map((iss) => Chip(
                                        label: Text(_label(iss),
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        backgroundColor:
                                            _color(iss).withOpacity(0.15),
                                        visualDensity: VisualDensity.compact,
                                      ))
                                  .toList(),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EntryFormScreen(
                                    controller: controller, entry: e, settings: settings),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}