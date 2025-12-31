import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/knowledgebase_api.dart';

class DHomescreen extends StatefulWidget {
  const DHomescreen({super.key});

  @override
  State<DHomescreen> createState() => _DHomescreenState();
}

class _DHomescreenState extends State<DHomescreen> {
  bool _uploading = false;
  bool _loadingRegistry = false;
  String? _status;

  List<Map<String, dynamic>> _registry = [];

  @override
  void initState() {
    super.initState();
    loadRegistry();
  }

  Future<void> loadRegistry() async {
    setState(() => _loadingRegistry = true);

    try {
      final data = await KnowledgebaseApi.showFiles();

      if (!mounted) return;
      setState(() {
        _registry = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = "Failed to load registry: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _loadingRegistry = false);
      }
    }
  }

  Future<void> _handleUpload() async {
    try {
      final file = await KnowledgebaseApi.pickFile();
      if (file == null) return;

      if (!mounted) return;
      setState(() {
        _uploading = true;
        _status = "Uploading ${file.name}...";
      });

      final result = await KnowledgebaseApi.uploadFile(file);

      if (!mounted) return;
      setState(() {
        _status = "Uploaded: ${result['filename'] ?? file.name}";
      });

      await loadRegistry();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = "Upload failed: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// ───── TOP HALF ─────
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Upcoming quizzes",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text("Results from last quiz"),
                  const SizedBox(height: 24),

                  const Text(
                    "Add file to knowledgebase",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  ElevatedButton(
                    onPressed: _uploading ? null : _handleUpload,
                    child:
                        _uploading
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text("Upload PDF"),
                  ),

                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_status!),
                    ),
                ],
              ),
            ),

            const Divider(),

            /// ───── BOTTOM HALF ─────
            Expanded(flex: 1, child: _buildRegistry()),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistry() {
    if (_loadingRegistry) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_registry.isEmpty) {
      return const Center(child: Text("No files uploaded yet"));
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _registry.length,
              itemBuilder: (context, index) {
                final file = _registry[index];

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf),

                    title: Text(
                      (file['original_name'] ?? 'Unnamed file').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    subtitle: Text(
                      "Converted: ${file['converted'] == 1 ? 'Yes' : 'No'} • "
                      "Embedded: ${file['embedded'] == 1 ? 'Yes' : 'No'}",
                    ),

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.transform),
                          tooltip: "Convert file",
                          onPressed: () {
                            //TODO: add conversion handler
                            _addFile(file);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.memory),
                          tooltip: "Embedd file",
                          onPressed: () {
                            //TODO: add embedd handler
                            _addFile(file);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: "Delete file",
                          onPressed: () {
                            _confirmDelete(file);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// ───── ACTION HANDLERS ─────

  void _addFile(Map<String, dynamic> file) {
    print("Add file: ${file['id']}");
    // TODO: hook into bubble / workspace logic
  }

  void _confirmDelete(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text("Delete file"),
            content: Text(
              "Are you sure you want to delete "
              "${file['original_name'] ?? 'this file'}?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                  _deleteFile(file);
                },
                child: const Text("Delete"),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    print("Deleting file: ${file['id']}");
    try {
      await KnowledgebaseApi.deleteFiles(
        file['original_name'],
        file['filepath'],
        file['fingerprint'],
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
    setState(() {
      _registry.remove(file);
    });
  }

  Future<void> _convertToMarkdown() async {
    try {
      await KnowledgebaseApi.convertMarkdown();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> _embeddFiles() async {
    try {
      await KnowledgebaseApi.embedFiles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }
}
