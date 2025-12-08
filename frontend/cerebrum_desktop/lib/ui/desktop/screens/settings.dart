import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/configs_api.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 1600,
        height: 800,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 2,
              offset: Offset(0, 5),
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

            // BODY ROW (Sidebar + Divider + Main content)
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
                      children: const [
                        Text("My Account", style: TextStyle(fontSize: 18)),
                        SizedBox(height: 12),
                        Text("Ollama", style: TextStyle(fontSize: 18)),
                        SizedBox(height: 12),
                        Text("System", style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),

                  // VERTICAL DIVIDER
                  const VerticalDivider(
                    width: 1,
                    thickness: 2,
                    color: Colors.black54,
                  ),

                  // MAIN CONTENT -> change content based on selected page
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("Ollama status"),
                            SizedBox(height: 12),
                            Text("Installed Chat Models"),
                            SizedBox(height: 12),
                            Text("Installed Embedding Models"),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
