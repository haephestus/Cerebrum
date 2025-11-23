import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/configs_api.dart';

class MSettings extends StatefulWidget {
  const MSettings({super.key});

  @override
  State<MSettings> createState() => _MSettingsState();
}

class _MSettingsState extends State<MSettings> {
  Map<String, dynamic> configs = {};

  @override
  void initState() {
    super.initState();
    fetchConfigs();
  }

  Future<void> fetchConfigs() async {
    try {
      final data = await ConfigsApi.fetchConfigs();
      setState(() => configs = data);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body:
          configs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children:
                    configs.entries.map((entry) {
                      final key = entry.key;
                      final value = entry.value;

                      return ListTile(
                        title: Text(key),
                        subtitle: Text(value.toString()),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // OPTIONAL: navigate to config editor
                        },
                      );
                    }).toList(),
              ),
    );
  }
}

