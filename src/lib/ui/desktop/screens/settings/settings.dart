import 'package:flutter/material.dart';
import 'package:cerebrum_app/ui/desktop/screens/settings/ollama_settings.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int selectedPage = 0;

  void changePage(int page) {
    setState(() {
      selectedPage = page;
    });
  }

  Widget _buildPage() {
    if (selectedPage == 0) {
      return const Text("User settings go here");
    } else if (selectedPage == 1) {
      return const OllamaSettings();
    } else if (selectedPage == 2) {
      return const Text("System settings go here");
    }
    return const Center(child: Text('Unknown Page'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // See-through background
      backgroundColor: Colors.black.withValues(alpha: 0.4),
      body: Center(
        child: Container(
          width: 1600,
          height: 800,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white, // solid popup
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              // HEADER ROW
              Row(
                children: [
                  const Text(
                    "Settings",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // BODY ROW (Sidebar + Main content)
              Expanded(
                child: Row(
                  children: [
                    // SIDEBAR
                    Container(
                      width: 200,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                            onPressed: () => changePage(0),
                            child: const Text("My account"),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => changePage(1),
                            child: const Text("Ollama"),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => changePage(2),
                            child: const Text("System"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // MAIN CONTENT
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.topCenter,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(child: _buildPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
