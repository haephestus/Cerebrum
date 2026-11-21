import 'package:cerebrum/api/knowledgebase_api.dart';
import 'package:cerebrum/services/reading_progress.dart';
import 'package:cerebrum/features/reader/reader.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:cerebrum/common/widgets/floating_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileLibrary extends StatefulWidget {
  const FileLibrary({
    super.key,
    this.onClose,
    this.onPick,
    this.initialFingerprint,
  });

  /// What the FloatingModal close button does. Inside a showDialog host
  /// this can stay null (the default Navigator.pop closes the route).
  /// When the widget is embedded as a sidebar page there is no route to
  /// pop, so the embedding page passes an explicit callback (see
  /// FloatingModal's header doc on embedded usage).
  final VoidCallback? onClose;

  /// Selection mode for hosts that need a fingerprint instead of a reader
  /// route (the editor's "Open document" dialog). When set, activating a row
  /// calls this and does NOT push the reader.
  final ValueChanged<String>? onPick;

  /// Row to preselect when the library opens, e.g. the editor's current book.
  final String? initialFingerprint;

  bool get pickMode => onPick != null;

  @override
  State<FileLibrary> createState() => _FileLibraryState();
}

class _FileLibraryState extends State<FileLibrary> {
  bool _loadingRegistry = false;
  String? _status;

  List<Map<String, dynamic>> _registry = [];

  // Client-side reading progress. The daemon's registry has no per-user
  // position, so these maps are hydrated from SharedPreferences (see
  // ReadingProgress) and refreshed after the reader closes.
  final Map<String, int> _lastPage = {};
  final Map<String, int> _lastOpened = {};

  final _search = TextEditingController();
  // The list owns focus by default so j/k work immediately. Typing happens
  // only after i (or /), which moves focus to the search field.
  final _listFocus = FocusNode(debugLabel: 'file-library-vim');
  final _searchFocus = FocusNode(debugLabel: 'file-library-search');
  final _scroll = ScrollController();

  String _query = '';
  String? _genre; // null = every genre
  bool _recentOnly = false;
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    loadRegistry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _listFocus.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> loadRegistry() async {
    if (mounted) setState(() => _loadingRegistry = true);

    try {
      final data = await KnowledgebaseApi.showFiles();
      final files = List<Map<String, dynamic>>.from(data);
      final meta = await _readLocalMeta(files);

      if (!mounted) return;
      setState(() {
        _registry = files;
        _lastPage
          ..clear()
          ..addAll(meta.pages);
        _lastOpened
          ..clear()
          ..addAll(meta.opened);
        final idx = _visible.indexWhere(
          (f) => _fp(f) == widget.initialFingerprint,
        );
        _sel = idx >= 0 ? idx : 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to load registry: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingRegistry = false);
      }
    }
  }

  Future<_LocalMeta> _readLocalMeta(List<Map<String, dynamic>> files) async {
    final sp = await SharedPreferences.getInstance();
    final pages = <String, int>{};
    final opened = <String, int>{};
    for (final f in files) {
      final fp = _fp(f);
      if (fp.isEmpty) continue;
      final page = sp.getInt(ReadingProgress.pageKey(fp));
      final openedAt = sp.getInt(ReadingProgress.openedKey(fp));
      if (page != null) pages[fp] = page;
      if (openedAt != null) opened[fp] = openedAt;
    }
    return _LocalMeta(pages, opened);
  }

  Future<void> _refreshLocalMeta() async {
    final meta = await _readLocalMeta(_registry);
    if (!mounted) return;
    setState(() {
      _lastPage
        ..clear()
        ..addAll(meta.pages);
      _lastOpened
        ..clear()
        ..addAll(meta.opened);
    });
  }

  // ---------------------------------------------------------------------------
  // Row metadata
  // ---------------------------------------------------------------------------

  String _fp(Map<String, dynamic> f) =>
      (f['file_fingerprint'] ?? '').toString();

  String _title(Map<String, dynamic> f) {
    final original = (f['original_name'] ?? '').toString().trim();
    if (original.isNotEmpty) return original;
    final sanitized = (f['sanitized_name'] ?? '').toString().trim();
    return sanitized.isNotEmpty ? sanitized : 'Unnamed file';
  }

  /// The daemon exposes `domain` and `subject`; there is no separate "genre"
  /// column. `domain` is the closest thing to a genre, so filter on it and
  /// fall back to a single bucket rather than inventing a taxonomy.
  String _genreOf(Map<String, dynamic> f) {
    final domain = (f['domain'] ?? '').toString().trim();
    if (domain.isNotEmpty && domain.toLowerCase() != 'null') return domain;
    return 'Uncategorized';
  }

  String _subjectOf(Map<String, dynamic> f) {
    final subject = (f['subject'] ?? '').toString().trim();
    return subject.toLowerCase() == 'null' ? '' : subject;
  }

  String _docTypeOf(Map<String, dynamic> f) {
    final type = (f['doc_type'] ?? '').toString().trim();
    if (type.isEmpty ||
        type.toLowerCase() == 'null' ||
        type.toLowerCase() == 'unknown') {
      return '';
    }
    return type;
  }

  List<String> get _genres {
    final set = <String>{};
    for (final f in _registry) {
      set.add(_genreOf(f));
    }
    final list =
        set.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    // "Uncategorized" is a fallback, not a real genre; keep it last.
    if (list.remove('Uncategorized')) list.add('Uncategorized');
    return list;
  }

  String _haystack(Map<String, dynamic> f) =>
      [
        _title(f),
        _genreOf(f),
        _subjectOf(f),
        _docTypeOf(f),
      ].join(' ').toLowerCase();

  List<Map<String, dynamic>> get _visible {
    final query = _query;
    final genre = _genre;
    final recentOnly = _recentOnly;
    final out = <Map<String, dynamic>>[];

    for (final f in _registry) {
      if (genre != null && _genreOf(f) != genre) continue;
      // A saved page is legacy evidence of reading even when this build never
      // wrote an opened timestamp (the timestamp key is newer than the page
      // key), so include it instead of hiding already-read books.
      if (recentOnly &&
          !_lastOpened.containsKey(_fp(f)) &&
          !_lastPage.containsKey(_fp(f))) {
        continue;
      }
      if (query.isNotEmpty && !_haystack(f).contains(query)) continue;
      out.add(f);
    }

    // Most recently read first; unread books fall back to title order.
    out.sort((a, b) {
      final openedA = _lastOpened[_fp(a)] ?? 0;
      final openedB = _lastOpened[_fp(b)] ?? 0;
      if (openedA != openedB) return openedB.compareTo(openedA);
      return _title(a).toLowerCase().compareTo(_title(b).toLowerCase());
    });
    return out;
  }

  // ---------------------------------------------------------------------------
  // Selection + navigation
  // ---------------------------------------------------------------------------

  static const _rowExtent = 96.0;

  void _move(int delta) {
    final count = _visible.length;
    if (count == 0) return;
    setState(() => _sel = (_sel + delta).clamp(0, count - 1));
    _ensureVisible();
  }

  void _ensureVisible() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.animateTo(
      (_sel * _rowExtent).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _setFilter({required String? genre, required bool recentOnly}) {
    setState(() {
      _genre = genre;
      _recentOnly = recentOnly;
      _sel = 0;
    });
    _listFocus.requestFocus();
    _ensureVisible();
  }

  void _activateCurrent() {
    final files = _visible;
    if (files.isEmpty) return;
    _activate(files[_sel.clamp(0, files.length - 1)]);
  }

  void _activate(Map<String, dynamic> file) {
    final fingerprint = _fp(file);
    if (fingerprint.isEmpty) return;

    final onPick = widget.onPick;
    if (onPick != null) {
      onPick(fingerprint);
      return;
    }
    _openReader(fingerprint);
  }

  Future<void> _openReader(String fingerprint) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Reader(fileFingerprint: fingerprint)),
    );
    if (!mounted) return;
    // The reader just updated the page/opened timestamps; re-sort the list.
    await _refreshLocalMeta();
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ch = event.character;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    const handled = KeyEventResult.handled;

    // Esc peels back one layer: leave search, then close the library.
    if (key == LogicalKeyboardKey.escape) {
      if (_searchFocus.hasFocus) {
        _searchFocus.unfocus();
        _listFocus.requestFocus();
      } else {
        _close();
      }
      return handled;
    }

    // While typing the field owns the keys: j/k must type, not navigate.
    // Enter is handled by onSubmitted.
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;

    final down =
        key == LogicalKeyboardKey.arrowDown ||
        (!shift && key == LogicalKeyboardKey.keyJ);
    final up =
        key == LogicalKeyboardKey.arrowUp ||
        (!shift && key == LogicalKeyboardKey.keyK);
    if (down) {
      _move(1);
      return handled;
    }
    if (up) {
      _move(-1);
      return handled;
    }
    if (key == LogicalKeyboardKey.home) {
      if (_visible.isNotEmpty) setState(() => _sel = 0);
      _ensureVisible();
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      final count = _visible.length;
      if (count > 0) setState(() => _sel = count - 1);
      _ensureVisible();
      return handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _activateCurrent();
      return handled;
    }
    // i (or /, the reader's search key) enters the search field. Match the
    // character so / works on layouts where it needs Shift.
    if (ch == 'i' || ch == '/') {
      _searchFocus.requestFocus();
      return handled;
    }
    // Swallow the rest so the shell behind the overlay can't act on them.
    return handled;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleUpload() async {
    try {
      final file = await KnowledgebaseApi.pickFile();
      if (file == null) return;

      if (!mounted) return;
      setState(() {
        _status = 'Uploading ${file.name}...';
      });

      final result = await KnowledgebaseApi.uploadFile(file);

      if (!mounted) return;
      setState(() {
        _status = 'Uploaded: ${result['filename'] ?? file.name}';
      });

      await loadRegistry();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Upload failed: $e';
      });
    }
  }

  void _confirmDelete(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete file'),
            content: Text(
              'Are you sure you want to delete '
              '${file['original_name'] ?? 'this file'}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _deleteFile(file);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    try {
      await KnowledgebaseApi.deleteFiles(file['file_fingerprint']);
      if (!mounted) return;
      setState(() {
        _registry.remove(file);
        _sel = _sel.clamp(0, _visible.isEmpty ? 0 : _visible.length - 1);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _processFile(String fileFingerprint) async {
    try {
      await KnowledgebaseApi.processFile(fileFingerprint);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _listFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: FloatingModal(
        title: widget.pickMode ? 'Open document' : 'File Library',
        onClose: widget.onClose,
        showIcon: true,
        toolTip: 'Upload file',
        onPressed: _handleUpload,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cerebrum.surface.outlineStrong,
                  ),
                ),
              ),
            TextField(
              controller: _search,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search books (i or /)',
                suffixIcon:
                    _query.isEmpty
                        ? null
                        : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() {
                              _query = '';
                              _sel = 0;
                            });
                            _listFocus.requestFocus();
                            _ensureVisible();
                          },
                        ),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim().toLowerCase();
                  _sel = 0;
                });
                _ensureVisible();
              },
              onSubmitted: (_) => _activateCurrent(),
            ),
            const SizedBox(height: 8),
            _buildFilters(),
            const SizedBox(height: 8),
            Expanded(child: _buildRegistry()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _genre == null && !_recentOnly,
              onSelected: (_) => _setFilter(genre: null, recentOnly: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Recently read'),
              selected: _recentOnly,
              onSelected: (_) => _setFilter(genre: null, recentOnly: true),
            ),
          ),
          for (final genre in _genres)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(genre),
                selected: _genre == genre,
                onSelected: (_) => _setFilter(genre: genre, recentOnly: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegistry() {
    if (_loadingRegistry) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_registry.isEmpty) {
      return const Center(child: Text('No files uploaded yet'));
    }

    final files = _visible;
    if (files.isEmpty) {
      return Center(
        child: Text(
          _recentOnly ? 'No recently read books yet' : 'No books match',
        ),
      );
    }

    final selected = _sel.clamp(0, files.length - 1);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.cerebrum.surface.outline),
        ),
      ),
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _rowExtent,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final isSelected = index == selected;
          return MouseRegion(
            onEnter: (_) {
              if (!isSelected) setState(() => _sel = index);
            },
            child: _buildRow(file, isSelected),
          );
        },
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> file, bool selected) {
    final fingerprint = _fp(file);
    final page = _lastPage[fingerprint];
    final openedAt = _lastOpened[fingerprint];
    final genre = _genreOf(file);
    final subject = _subjectOf(file);
    final docType = _docTypeOf(file);

    final meta = [
      genre,
      if (subject.isNotEmpty && subject != genre) subject,
      if (docType.isNotEmpty) docType,
    ].join(' · ');

    final String progress;
    if (openedAt != null) {
      progress =
          page != null && page > 1
              ? 'Read ${_ago(openedAt)} · p. $page'
              : 'Read ${_ago(openedAt)}';
    } else if (page != null && page > 1) {
      // Legacy progress: the page was saved before opened timestamps existed.
      progress = 'p. $page';
    } else {
      progress = 'Not read yet';
    }
    final converted = file['converted'] == 1;
    final embedded = file['embedded'] == 1;
    final status = [
      converted ? 'converted' : 'not converted',
      if (embedded) 'embedded',
    ].join(' · ');

    final current = fingerprint == widget.initialFingerprint;

    return ListTile(
      selected: selected,
      leading: const Icon(Icons.picture_as_pdf),
      title: Text(_title(file), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$meta\n$progress · $status',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing:
          widget.pickMode
              ? (current ? const Icon(Icons.check, size: 18) : null)
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.memory),
                    tooltip: 'Process file',
                    onPressed: () => _processFile(fingerprint),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete file',
                    onPressed: () => _confirmDelete(file),
                  ),
                ],
              ),
      enabled: fingerprint.isNotEmpty,
      onTap: fingerprint.isEmpty ? null : () => _activate(file),
    );
  }

  static String _ago(int millis) {
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(millis),
    );
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

class _LocalMeta {
  const _LocalMeta(this.pages, this.opened);

  final Map<String, int> pages;
  final Map<String, int> opened;
}
