import 'package:cerebrum_app/api/configs_api.dart';
import 'package:flutter/material.dart';

class Setting extends StatefulWidget {
  const Setting({super.key});

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  List<dynamic> installedchatmodels = [];

  Future<void> fetchInstalledChat() async {
    try {
      final data = await ConfigsApi.fetchInstalledChatModels();
      setState(() => installedchatmodels = data);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  @override
  void initState() {
    super.initState();
    fetchInstalledChat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Installed Chat Models")),
      body: ListView.builder(
        itemCount: installedchatmodels.length,
        itemBuilder: (context, index) {
          return ListTile(title: Text(installedchatmodels[index].toString()));
        },
      ),
    );
  }
}
