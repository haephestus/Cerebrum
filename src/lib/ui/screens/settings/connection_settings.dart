import 'package:flutter/material.dart';
import 'package:cerebrum/api/api_config.dart';
import 'package:cerebrum/services/user_session.dart';

/// Connection settings: pick which daemon to talk to (local vs cloud), set the
/// base URL for each, and enter the local-mode daemon key. Persists via
/// [ApiConfig] (mode + URLs) and [UserSession] (daemon key, stored securely).
class ConnectionSettings extends StatefulWidget {
  const ConnectionSettings({super.key});

  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  final _localUrlController = TextEditingController();
  final _cloudUrlController = TextEditingController();
  final _daemonKeyController = TextEditingController();

  DeploymentMode _mode = DeploymentMode.local;
  bool _obscureKey = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final local = await ApiConfig.urlFor(DeploymentMode.local);
    final cloud = await ApiConfig.urlFor(DeploymentMode.cloud);
    final key = await UserSession.getDaemonKey();
    if (!mounted) return;
    setState(() {
      _mode = ApiConfig.mode;
      _localUrlController.text = local;
      _cloudUrlController.text = cloud;
      _daemonKeyController.text = key ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _localUrlController.dispose();
    _cloudUrlController.dispose();
    _daemonKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiConfig.setBaseUrl(
          DeploymentMode.local, _localUrlController.text.trim());
      await ApiConfig.setBaseUrl(
          DeploymentMode.cloud, _cloudUrlController.text.trim());
      await ApiConfig.setMode(_mode); // sets active baseUrl for the chosen mode
      await UserSession.saveDaemonKey(_daemonKeyController.text.trim());
      messenger.showSnackBar(
        const SnackBar(content: Text('Connection settings saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Connection',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Which daemon this app talks to.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),
        SegmentedButton<DeploymentMode>(
          segments: const [
            ButtonSegment(
              value: DeploymentMode.local,
              label: Text('Local'),
              icon: Icon(Icons.computer),
            ),
            ButtonSegment(
              value: DeploymentMode.cloud,
              label: Text('Cloud'),
              icon: Icon(Icons.cloud),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _localUrlController,
          decoration: const InputDecoration(
            labelText: 'Local daemon URL',
            hintText: 'http://localhost:8000',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cloudUrlController,
          decoration: const InputDecoration(
            labelText: 'Cloud daemon URL',
            hintText: 'https://your-app.leapcell.dev',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _daemonKeyController,
          obscureText: _obscureKey,
          decoration: InputDecoration(
            labelText: 'Daemon key (local mode)',
            helperText: 'Printed by the daemon on startup. Not used in cloud mode.',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}
