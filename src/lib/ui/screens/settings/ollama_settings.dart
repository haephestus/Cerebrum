import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/api/configs_api.dart';

class OllamaSettings extends StatefulWidget {
  const OllamaSettings({super.key});

  @override
  State<OllamaSettings> createState() => _OllamaSettingsState();
}

class _OllamaSettingsState extends State<OllamaSettings> {
  bool loading = false;

  String? selectedChatModel;
  String? selectedEmbeddingModel;

  List<String> installedChatModels = [];
  List<String> installedEmbeddingModels = [];

  List<String> onlineChatModels = [];
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
    try {
      final config = await ConfigsApi.fetchConfigs();
      selectedChatModel = config["models"]["chat_model"];
      selectedEmbeddingModel = config["models"]["embedding_model"];

      final chatResp = await ConfigsApi.fetchInstalledChatModels();
      installedChatModels = List<String>.from(
        chatResp["installed_chat_models"] ?? [],
      );

      final embResp = await ConfigsApi.fetchInstalledEmbeddingModels();
      installedEmbeddingModels = List<String>.from(
        embResp["installed_embedding_models"] ?? [],
      );

      final onlineResp = await ConfigsApi.fetchOnlineModels();

      onlineChatModels =
          List<String>.from(
            onlineResp["online_chat_models"] ?? [],
          ).where((m) => !installedChatModels.contains(m)).toList();

      onlineEmbeddingModels =
          List<String>.from(
            onlineResp["online_embedding_models"] ?? [],
          ).where((m) => !installedEmbeddingModels.contains(m)).toList();

      setState(() => loading = false);
    } catch (e) {
      print("Error loading models: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading: $e"),
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => loading = false);
      }
    }
  }

  Future<void> onChatModelChanged(String newModel) async {
    final needsDownload = !installedChatModels.contains(newModel);

    String modelToSet = newModel;

    if (needsDownload) {
      // Show model details dialog
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

    // Always update the config after download or selection
    setState(() => selectedChatModel = modelToSet);

    try {
      await ConfigsApi.updateChatModel(modelToSet);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Chat model updated to $modelToSet")),
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
      // Show model details dialog
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

    // Always update the config after download or selection
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
      barrierColor: context.cerebrum.text.muted,
      barrierDismissible: true, // Allow clicking outside to dismiss
      builder: (context) => _ModelDetailsDialog(modelName: modelName),
    );
  }

  Widget _buildModelDropdown({
    required String label,
    required String? selectedModel,
    required List<String> installedModels,
    required List<String> onlineModels,
    required Function(String) onChanged,
    required bool installedExpanded,
    required bool onlineExpanded,
    required VoidCallback onInstalledToggle,
    required VoidCallback onOnlineToggle,
    required String searchQuery,
    required Function(String) onSearchChanged,
  }) {
    // Filter online models based on search query
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
            color: context.cerebrum.surface.sunken,
            border: Border.all(color: context.cerebrum.surface.outline),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Installed Models Section
              InkWell(
                onTap: onInstalledToggle,
                child: Row(
                  children: [
                    Icon(
                      installedExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: context.cerebrum.text.strong,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: context.cerebrum.status.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Installed Models",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.cerebrum.text.strong,
                        ),
                      ),
                    ),
                    Text(
                      "(${installedModels.length})",
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cerebrum.surface.outlineStrong,
                      ),
                    ),
                  ],
                ),
              ),
              if (installedExpanded) ...[
                const SizedBox(height: 6),
                if (installedModels.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: 30, bottom: 8),
                    child: Text(
                      "No models installed",
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cerebrum.surface.outlineStrong,
                      ),
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
                                  ? context.cerebrum.status.infoSurface
                                  : context.cerebrum.surface.raised,
                          border: Border.all(
                            color:
                                selectedModel == model
                                    ? context.cerebrum.status.info
                                    : context.cerebrum.surface.outline,
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
                                          ? context.cerebrum.status.info
                                          : context.cerebrum.text.strong,
                                ),
                              ),
                            ),
                            if (selectedModel == model)
                              Icon(
                                Icons.check,
                                size: 16,
                                color: context.cerebrum.status.info,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],

              const SizedBox(height: 12),

              // Available Models Section
              InkWell(
                onTap: onOnlineToggle,
                child: Row(
                  children: [
                    Icon(
                      onlineExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: context.cerebrum.text.strong,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.cloud_download,
                      size: 16,
                      color: context.cerebrum.status.info,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Models You Can Download",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.cerebrum.text.strong,
                        ),
                      ),
                    ),
                    Text(
                      "(${onlineModels.length})",
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cerebrum.surface.outlineStrong,
                      ),
                    ),
                  ],
                ),
              ),
              if (onlineExpanded) ...[
                const SizedBox(height: 8),

                // Search Bar
                Container(
                  margin: const EdgeInsets.only(left: 30, right: 0),
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
                      fillColor: context.cerebrum.surface.raised,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: context.cerebrum.surface.outline,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: context.cerebrum.surface.outline,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: context.cerebrum.status.info,
                        ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cerebrum.surface.outlineStrong,
                      ),
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
                              color: context.cerebrum.surface.raised,
                              border: Border.all(
                                color: context.cerebrum.surface.outline,
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
                                      color: context.cerebrum.text.strong,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.cloud_download,
                                  size: 14,
                                  color: context.cerebrum.status.info,
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
              style: TextStyle(
                fontSize: 12,
                color: context.cerebrum.surface.outlineStrong,
              ),
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
                  ollamaRunning
                      ? context.cerebrum.status.successSurface
                      : context.cerebrum.status.warningSurface,
              border: Border.all(
                color:
                    ollamaRunning
                        ? context.cerebrum.status.successSoft
                        : context.cerebrum.surface.outline,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  ollamaRunning ? Icons.check_circle : Icons.warning,
                  color:
                      ollamaRunning
                          ? context.cerebrum.status.success
                          : context.cerebrum.status.warning,
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
                                  ? context.cerebrum.status.success
                                  : context.cerebrum.status.warningStrong,
                        ),
                      ),
                      if (!ollamaRunning && ollamaInstalled)
                        Text(
                          "Please start Ollama to manage models",
                          style: TextStyle(
                            fontSize: 12,
                            color: context.cerebrum.text.muted,
                          ),
                        ),
                      if (!ollamaInstalled)
                        Text(
                          "Install Ollama from ollama.com/download",
                          style: TextStyle(
                            fontSize: 12,
                            color: context.cerebrum.text.muted,
                          ),
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

          _buildModelDropdown(
            label: "Chat Model",
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
        // Select "latest" by default if available
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
              // Description
              if (modelInfo!['description'] != null) ...[
                Text(
                  modelInfo!['description'],
                  style: TextStyle(
                    fontSize: 14,
                    color: context.cerebrum.text.strong,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Available Versions
              const Text(
                "Available Versions",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),

              if (modelInfo!['tags'] == null ||
                  (modelInfo!['tags'] as List).isEmpty)
                Text(
                  "No versions available",
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cerebrum.surface.outlineStrong,
                  ),
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
                                isSelected
                                    ? context.cerebrum.status.infoSurface
                                    : context.cerebrum.surface.raised,
                            border: Border.all(
                              color:
                                  isSelected
                                      ? context.cerebrum.status.info
                                      : context.cerebrum.surface.outline,
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
                                                    ? context
                                                        .cerebrum
                                                        .status
                                                        .info
                                                    : context
                                                        .cerebrum
                                                        .text
                                                        .strong,
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
                                                color:
                                                    context
                                                        .cerebrum
                                                        .status
                                                        .info,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              "latest",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    context
                                                        .cerebrum
                                                        .status
                                                        .info,
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
                                          color: context.cerebrum.text.muted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: context.cerebrum.status.info,
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

              // Action Buttons
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
