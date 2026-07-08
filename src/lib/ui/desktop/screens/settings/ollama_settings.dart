import 'package:flutter/material.dart';
import 'package:cerebrum_app/api/configs_api.dart';

class OllamaSettings extends StatefulWidget {
  const OllamaSettings({super.key});

  @override
  State<OllamaSettings> createState() => _OllamaSettingsState();
}

class _OllamaSettingsState extends State<OllamaSettings> {
  bool loading = false;

  String? selectedChatModel;
  String? selectedEmbeddingModel;
  String? selectedCloudModel;

  List<String> installedChatModels = [];
  List<String> installedEmbeddingModels = [];

  List<String> onlineChatModels = [];
  List<String> cloudModels = [];
  List<String> onlineEmbeddingModels = [];

  bool chatInstalledExpanded = true;
  bool chatOnlineExpanded = false;
  bool embeddingInstalledExpanded = true;
  bool embeddingOnlineExpanded = false;

  bool ollamaInstalled = false;
  bool ollamaRunning = false;
  String ollamaMessage = "";
  bool checkingStatus = true;

  String chatSearchQuery = "";
  String embeddingSearchQuery = "";

  @override
  void initState() {
    super.initState();
    checkOllamaStatus();
    loadAll();
  }

  Future<void> checkOllamaStatus() async {
    setState(() => checkingStatus = true);
    try {
      final status = await ConfigsApi.fetchOllamaStatus();
      setState(() {
        ollamaInstalled = status["installed"] ?? false;
        ollamaRunning = status["running"] ?? false;
        ollamaMessage = status["message"] ?? "";
        checkingStatus = false;
      });
    } catch (e) {
      print("Error checking Ollama status: $e");
      setState(() {
        ollamaInstalled = false;
        ollamaRunning = false;
        ollamaMessage = "Failed to check Ollama status";
        checkingStatus = false;
      });
    }
  }

  Future<void> loadAll() async {
    setState(() => loading = true);

    // 1. Fire off all API requests in parallel safely
    final results = await Future.wait([
      ConfigsApi.fetchConfigs().catchError((e) => <String, dynamic>{}),
      ConfigsApi.fetchInstalledChatModels().catchError(
        (e) => <String, dynamic>{},
      ),
      ConfigsApi.fetchInstalledEmbeddingModels().catchError(
        (e) => <String, dynamic>{},
      ),
      ConfigsApi.fetchLocalModels().catchError((e) => <String, dynamic>{}),
      ConfigsApi.fetchCloudModels().catchError((e) => <String, dynamic>{}),
    ]);

    final config = results[0];
    final chatResp = results[1];
    final embResp = results[2];
    final onlineResp = results[3];
    final cloudResp = results[4];

    setState(() {
      // 2. Safely parse active selections
      if (config.containsKey("models")) {
        selectedChatModel = config["models"]["chat_model"];
        selectedEmbeddingModel = config["models"]["embedding_model"];
        selectedCloudModel = config["models"]["cloud_model"];
      }

      // 3. Extract your dynamic local installation array states
      installedChatModels = List<String>.from(
        chatResp["installed_chat_models"] ?? [],
      );

      installedEmbeddingModels = List<String>.from(
        embResp["installed_embedding_models"] ?? [],
      );

      // 4. Safely fall back to parsing string arrays or complex dictionary lists from manifest
      var rawOnlineChat = onlineResp["online_chat_models"] as List? ?? [];
      onlineChatModels =
          rawOnlineChat
              .map((m) => m is String ? m : m["name"].toString())
              .where((m) => !installedChatModels.contains(m))
              .toList();

      var rawOnlineEmbed = onlineResp["online_embedding_models"] as List? ?? [];
      onlineEmbeddingModels =
          rawOnlineEmbed
              .map((m) => m is String ? m : m["name"].toString())
              .where((m) => !installedEmbeddingModels.contains(m))
              .toList();

      // 5. Extract available cloud models
      cloudModels = List<String>.from(cloudResp["cloud_models"] ?? []);

      loading = false;
    });
  }

  Future<void> onChatModelChanged(String newModel) async {
    final needsDownload = !installedChatModels.contains(newModel);
    String modelToSet = newModel;

    if (needsDownload) {
      final selectedVersion = await _showModelDetailsDialog(context, newModel);
      if (selectedVersion == null) return;

      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Downloading $selectedVersion..."),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        await ConfigsApi.downloadModel(selectedVersion);
        setState(() {
          installedChatModels.add(selectedVersion);
          onlineChatModels.remove(newModel);
        });
        modelToSet = selectedVersion;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$selectedVersion downloaded successfully!"),
            ),
          );
        }
      } catch (e) {
        print("Download error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Download failed: $e"),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    }

    setState(() => selectedChatModel = modelToSet);

    try {
      await ConfigsApi.updateChatModel(modelToSet);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Local model updated to $modelToSet")),
        );
      }
    } catch (e) {
      print("Update error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Update failed: $e"),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> onCloudModelChanged(String newModel) async {
    final selectedTag = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      builder: (context) => _CloudTagDialog(modelName: newModel),
    );

    if (selectedTag == null) return;

    setState(() => selectedCloudModel = selectedTag);

    try {
      await ConfigsApi.updateCloudModel(selectedTag);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cloud model updated to $selectedTag")),
        );
      }
    } catch (e) {
      print("Update error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Update failed: $e"),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> onEmbeddingModelChanged(String newModel) async {
    final needsDownload = !installedEmbeddingModels.contains(newModel);
    String modelToSet = newModel;

    if (needsDownload) {
      final selectedVersion = await _showModelDetailsDialog(context, newModel);
      if (selectedVersion == null) return;

      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Downloading $selectedVersion..."),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        await ConfigsApi.downloadModel(selectedVersion);
        setState(() {
          installedEmbeddingModels.add(selectedVersion);
          onlineEmbeddingModels.remove(newModel);
        });
        modelToSet = selectedVersion;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$selectedVersion downloaded successfully!"),
            ),
          );
        }
      } catch (e) {
        print("Download error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Download failed: $e"),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    }

    setState(() => selectedEmbeddingModel = modelToSet);

    try {
      await ConfigsApi.updateEmbeddingModel(modelToSet);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Embedding model updated to $modelToSet")),
        );
      }
    } catch (e) {
      print("Update error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Update failed: $e"),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<String?> _showModelDetailsDialog(
    BuildContext context,
    String modelName,
  ) async {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      builder: (context) => _ModelDetailsDialog(modelName: modelName),
    );
  }

  Widget _buildModelDropdown({
    required String label,
    required String? selectedModel,
    required List<String>? installedModels,
    required List<String> onlineModels,
    required Function(String) onChanged,
    required bool? installedExpanded,
    required bool? onlineExpanded,
    required VoidCallback? onInstalledToggle,
    required VoidCallback? onOnlineToggle,
    required String searchQuery,
    required Function(String) onSearchChanged,
  }) {
    final filteredOnlineModels =
        searchQuery.isEmpty
            ? onlineModels
            : onlineModels
                .where(
                  (model) =>
                      model.toLowerCase().contains(searchQuery.toLowerCase()),
                )
                .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onInstalledToggle,
                child: Row(
                  children: [
                    Icon(
                      installedExpanded!
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        "Installed Models",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      "(${installedModels!.length})",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (installedExpanded) ...[
                const SizedBox(height: 6),
                if (installedModels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 30, bottom: 8),
                    child: Text(
                      "No models installed",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else
                  ...installedModels.map(
                    (model) => InkWell(
                      onTap: () => onChanged(model),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        margin: const EdgeInsets.only(left: 30, bottom: 4),
                        decoration: BoxDecoration(
                          color:
                              selectedModel == model
                                  ? Colors.blue.shade50
                                  : Colors.white,
                          border: Border.all(
                            color:
                                selectedModel == model
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                model,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      selectedModel == model
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                  color:
                                      selectedModel == model
                                          ? Colors.blue.shade900
                                          : Colors.black87,
                                ),
                              ),
                            ),
                            if (selectedModel == model)
                              Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.blue.shade700,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],

              const SizedBox(height: 12),

              InkWell(
                onTap: onOnlineToggle,
                child: Row(
                  children: [
                    Icon(
                      onlineExpanded!
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.cloud_download,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        "Models You Can Download",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      "(${onlineModels.length})",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (onlineExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.only(left: 30),
                  child: TextField(
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "Search models...",
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon:
                          searchQuery.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => onSearchChanged(""),
                              )
                              : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                if (filteredOnlineModels.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 30, top: 8),
                    child: Text(
                      searchQuery.isEmpty
                          ? "No additional models available"
                          : "No models found for '$searchQuery'",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredOnlineModels.length,
                      itemBuilder: (context, index) {
                        final model = filteredOnlineModels[index];
                        return InkWell(
                          onTap: () => onChanged(model),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            margin: const EdgeInsets.only(left: 30, bottom: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.cloud_download,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (selectedModel != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              "Current: $selectedModel",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),

          // Ollama Status Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  ollamaRunning ? Colors.green.shade50 : Colors.orange.shade50,
              border: Border.all(
                color:
                    ollamaRunning
                        ? Colors.green.shade300
                        : Colors.orange.shade300,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  ollamaRunning ? Icons.check_circle : Icons.warning,
                  color: ollamaRunning ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ollamaMessage,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              ollamaRunning
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                        ),
                      ),
                      if (!ollamaRunning && ollamaInstalled)
                        const Text(
                          "Please start Ollama to manage models",
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      if (!ollamaInstalled)
                        const Text(
                          "Install Ollama from ollama.com/download",
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                ),
                if (checkingStatus)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: checkOllamaStatus,
                    tooltip: "Refresh status",
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // CLOUD MODEL
          _CloudModelSelector(
            cloudModels: cloudModels,
            selectedModel: selectedCloudModel,
            onChanged: onCloudModelChanged,
          ),

          const SizedBox(height: 20),

          // CHAT MODEL
          _buildModelDropdown(
            label: "Local Model",
            selectedModel: selectedChatModel,
            installedModels: installedChatModels,
            onlineModels: onlineChatModels,
            onChanged: onChatModelChanged,
            installedExpanded: chatInstalledExpanded,
            onlineExpanded: chatOnlineExpanded,
            onInstalledToggle: () {
              setState(() => chatInstalledExpanded = !chatInstalledExpanded);
            },
            onOnlineToggle: () {
              setState(() => chatOnlineExpanded = !chatOnlineExpanded);
            },
            searchQuery: chatSearchQuery,
            onSearchChanged: (query) {
              setState(() => chatSearchQuery = query);
            },
          ),

          const SizedBox(height: 24),

          // EMBEDDING MODEL
          _buildModelDropdown(
            label: "Embedding Model",
            selectedModel: selectedEmbeddingModel,
            installedModels: installedEmbeddingModels,
            onlineModels: onlineEmbeddingModels,
            onChanged: onEmbeddingModelChanged,
            installedExpanded: embeddingInstalledExpanded,
            onlineExpanded: embeddingOnlineExpanded,
            onInstalledToggle: () {
              setState(
                () => embeddingInstalledExpanded = !embeddingInstalledExpanded,
              );
            },
            onOnlineToggle: () {
              setState(
                () => embeddingOnlineExpanded = !embeddingOnlineExpanded,
              );
            },
            searchQuery: embeddingSearchQuery,
            onSearchChanged: (query) {
              setState(() => embeddingSearchQuery = query);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Cloud Model Selector Widget
// ─────────────────────────────────────────────────────────────
class _CloudModelSelector extends StatefulWidget {
  final List<String> cloudModels;
  final String? selectedModel;
  final Function(String) onChanged;

  const _CloudModelSelector({
    required this.cloudModels,
    required this.selectedModel,
    required this.onChanged,
  });

  @override
  State<_CloudModelSelector> createState() => _CloudModelSelectorState();
}

class _CloudModelSelectorState extends State<_CloudModelSelector> {
  bool expanded = false;
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final filtered =
        searchQuery.isEmpty
            ? widget.cloudModels
            : widget.cloudModels
                .where(
                  (m) => m.toLowerCase().contains(searchQuery.toLowerCase()),
                )
                .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Cloud Model",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => expanded = !expanded),
                child: Row(
                  children: [
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: Colors.black87,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.cloud, size: 16, color: Colors.cyan),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        "Available Cloud Models",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      "(${widget.cloudModels.length})",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  onChanged: (q) => setState(() => searchQuery = q),
                  decoration: InputDecoration(
                    hintText: "Search cloud models...",
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon:
                        searchQuery.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => searchQuery = "");
                              },
                            )
                            : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.cyan),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      searchQuery.isEmpty
                          ? "No cloud models available"
                          : "No models found for '$searchQuery'",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final model = filtered[index];
                        final isSelected =
                            widget.selectedModel == model ||
                            (widget.selectedModel?.startsWith("$model:") ??
                                false);
                        return InkWell(
                          onTap: () => widget.onChanged(model),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color:
                                  isSelected
                                      ? Colors.cyan.shade50
                                      : Colors.white,
                              border: Border.all(
                                color:
                                    isSelected
                                        ? Colors.cyan
                                        : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight:
                                          isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                      color:
                                          isSelected
                                              ? Colors.cyan.shade900
                                              : Colors.black87,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.cyan.shade700,
                                  )
                                else
                                  const Icon(
                                    Icons.cloud,
                                    size: 14,
                                    color: Colors.cyan,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (widget.selectedModel != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              "Current: ${widget.selectedModel}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Cloud Tag Picker Dialog
// ─────────────────────────────────────────────────────────────
class _CloudTagDialog extends StatefulWidget {
  final String modelName;
  const _CloudTagDialog({required this.modelName});

  @override
  State<_CloudTagDialog> createState() => _CloudTagDialogState();
}

class _CloudTagDialogState extends State<_CloudTagDialog> {
  bool loading = true;
  List<String> cloudTags = [];
  String? selectedTag;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ConfigsApi.fetchCloudDetails(widget.modelName);
      setState(() {
        cloudTags = List<String>.from(resp["cloud_tags"] ?? []);
        selectedTag = cloudTags.isNotEmpty ? cloudTags.first : null;
        loading = false;
      });
    } catch (e) {
      print("Error loading cloud tags: $e");
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.modelName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Select a cloud tag to use",
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (cloudTags.isEmpty)
              const Text(
                "No cloud tags found for this model",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              )
            else
              ...cloudTags.map(
                (tag) => InkWell(
                  onTap: () => setState(() => selectedTag = tag),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color:
                          selectedTag == tag
                              ? Colors.cyan.shade50
                              : Colors.white,
                      border: Border.all(
                        color:
                            selectedTag == tag
                                ? Colors.cyan
                                : Colors.grey.shade300,
                        width: selectedTag == tag ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud, size: 16, color: Colors.cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  selectedTag == tag
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                              color:
                                  selectedTag == tag
                                      ? Colors.cyan.shade900
                                      : Colors.black87,
                            ),
                          ),
                        ),
                        if (selectedTag == tag)
                          Icon(
                            Icons.check_circle,
                            color: Colors.cyan.shade700,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      selectedTag == null
                          ? null
                          : () => Navigator.pop(context, selectedTag),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Use"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Model Details Dialog (for chat/embedding download)
// ─────────────────────────────────────────────────────────────
class _ModelDetailsDialog extends StatefulWidget {
  final String modelName;
  const _ModelDetailsDialog({required this.modelName});

  @override
  State<_ModelDetailsDialog> createState() => _ModelDetailsDialogState();
}

class _ModelDetailsDialogState extends State<_ModelDetailsDialog> {
  bool loading = true;
  Map<String, dynamic>? modelInfo;
  String? selectedTag;

  @override
  void initState() {
    super.initState();
    loadModelDetails();
  }

  Future<void> loadModelDetails() async {
    try {
      final info = await ConfigsApi.fetchModelDetails(widget.modelName);
      setState(() {
        modelInfo = info;
        loading = false;
        if (info['tags'] != null && (info['tags'] as List).isNotEmpty) {
          selectedTag = info['tags'][0];
        }
      });
    } catch (e) {
      print("Error loading model details: $e");
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.modelName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (modelInfo == null)
              const Expanded(
                child: Center(child: Text("Failed to load model details")),
              )
            else ...[
              if (modelInfo!['description'] != null) ...[
                Text(
                  modelInfo!['description'],
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 20),
              ],
              const Text(
                "Available Versions",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (modelInfo!['tags'] == null ||
                  (modelInfo!['tags'] as List).isEmpty)
                const Text(
                  "No versions available",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: (modelInfo!['tags'] as List).length,
                    itemBuilder: (context, index) {
                      final tagObj = modelInfo!['tags'][index];
                      final tag = tagObj is String ? tagObj : tagObj['name'];
                      final details =
                          tagObj is Map ? (tagObj['details'] ?? '') : '';
                      final isLatest =
                          tagObj is Map
                              ? (tagObj['is_latest'] ?? false)
                              : false;
                      final isSelected = selectedTag == tag;

                      return InkWell(
                        onTap: () => setState(() => selectedTag = tag),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color:
                                isSelected ? Colors.blue.shade50 : Colors.white,
                            border: Border.all(
                              color:
                                  isSelected
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          "${widget.modelName}:$tag",
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                            color:
                                                isSelected
                                                    ? Colors.blue.shade900
                                                    : Colors.black87,
                                          ),
                                        ),
                                        if (isLatest) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.blue,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              "latest",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (details.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        details,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.blue.shade700,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        selectedTag == null
                            ? null
                            : () => Navigator.pop(
                              context,
                              "${widget.modelName}:$selectedTag",
                            ),
                    child: const Text("Download & Use"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
