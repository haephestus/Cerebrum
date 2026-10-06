import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

import 'package:cerebrum/api/knowledgebase_api.dart';
import 'file_library.dart';

/// Dashboard's entry point into the file library: a single compact row, not
/// an embedded browser. Tapping it pops the existing [FileLibrary] widget
/// open in a modal dialog -- per direction, the file library is its own
/// thing now, not dashboard real estate.
///
/// TODO(agent): this only shows a total file count as the teaser. The
/// original ask was for a dashboard preview of "recently added" or "not
/// opened in a while" files, but that needs timestamp fields this codebase
/// doesn't confirm exist -- file_library.dart's registry rows only read
/// `original_name`, `converted`, `embedded`, and `file_fingerprint` from
/// KnowledgebaseApi.showFiles(). If the daemon's file records carry a
/// created-at or last-opened-at field, thread it through here and swap the
/// count teaser for a real 2-3 item preview list, sorted accordingly.
///
/// TODO(agent): a dedicated full-screen file manager (its own route, not a
/// dialog) is a larger piece of navigation/IA work than this widget can
/// decide on its own -- it needs a place in the app's navigation shell
/// (sidebar entry? own tab?) which isn't this file's call to make.
class FileLibraryLauncher extends StatefulWidget {
  const FileLibraryLauncher({super.key});

  @override
  State<FileLibraryLauncher> createState() => _FileLibraryLauncherState();
}

class _FileLibraryLauncherState extends State<FileLibraryLauncher> {
  int? _fileCount;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final data = await KnowledgebaseApi.showFiles();
      if (!mounted) return;
      setState(() => _fileCount = data.length);
    } catch (_) {
      // Silent -- the launcher still works without a count.
    }
  }

  void _openLibrary() {
    showDialog(
      context: context,
      builder:
          (dialogContext) => Dialog(
            // TODO: make this responsive
            child: SizedBox(width: 800, height: 800, child: FileLibrary()),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final countLabel = _fileCount == null ? '' : '$_fileCount files';
    return Material(
      color: context.cerebrum.surface.sunken,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openLibrary,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                color: context.cerebrum.brand.primary,
              ),
              const SizedBox(width: 10),
              const Text(
                'File Library',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (countLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  countLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cerebrum.text.muted,
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.cerebrum.text.disabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
