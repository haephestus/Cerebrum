import 'dart:io';

import 'package:cerebrum/services/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Hermetic stand-in for the platform directory provider: returns sandboxed
/// paths so the tests never touch the real user home or Documents folder.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider({required this.supportPath, this.documentsPath});

  final String supportPath;
  final String? documentsPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('cerebrum_paths_test');
  });

  tearDown(() {
    StoragePaths.resetForTest();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('resolves the data root under the app-support directory', () async {
    // documentsPath == null models the old Linux failure: no documents
    // directory resolvable (xdg-user-dir missing). The resolver must NOT
    // depend on it.
    PathProviderPlatform.instance = _FakePathProvider(
      supportPath: '${sandbox.path}/share/cerebrum_test',
      documentsPath: null,
    );

    final root = await StoragePaths.cerebrumRoot();

    expect(root.path, '${sandbox.path}/share/cerebrum_test/cerebrum');
    expect(root.existsSync(), isTrue);
  });

  test('migrates legacy documents-dir data once, then keeps the root', () async {
    final documents = Directory('${sandbox.path}/Documents')
      ..createSync(recursive: true);
    final legacy = Directory('${documents.path}/cerebrum')
      ..createSync(recursive: true);
    File('${legacy.path}/cerebrum.db').writeAsStringSync('legacy-data');
    File('${legacy.path}/bubbles/.keep').createSync(recursive: true);

    PathProviderPlatform.instance = _FakePathProvider(
      supportPath: '${sandbox.path}/share/cerebrum_test',
      documentsPath: documents.path,
    );

    final root = await StoragePaths.cerebrumRoot();
    expect(File('${root.path}/cerebrum.db').readAsStringSync(), 'legacy-data');
    expect(File('${root.path}/bubbles/.keep').existsSync(), isTrue);
    expect(legacy.existsSync(), isFalse); // moved, not copied

    // Memoized: a second call resolves to the same root, no re-migration.
    final again = await StoragePaths.cerebrumRoot();
    expect(again.path, root.path);
  });
}