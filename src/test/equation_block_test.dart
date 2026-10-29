import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cerebrum/ui/themes/default.dart';
import 'package:cerebrum/ui/themes/tokens/default_palette.dart';
import 'package:cerebrum/ui/screens/editor/blocks/equation/equation_block_component.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorState editorWith(Node equation) => EditorState(
    document: Document(
      root: Node(
        type: 'page',
        children: [
          paragraphNode(text: 'before'),
          equation,
          paragraphNode(text: 'after'),
        ],
      ),
    ),
  );

  Map<String, BlockComponentBuilder> builderMap() => {
    ...standardBlockComponentBuilderMap,
    kEquationBlockType: EquationBlockComponentBuilder(),
  };

  Future<void> pumpEditor(WidgetTester tester, EditorState state) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDefaultTheme(
          brightness: Brightness.dark,
          tokens: cerebrumDarkTokens,
        ),
        home: Provider<EditorState>.value(
          value: state,
          child: Scaffold(
            body: AppFlowyEditor(
              editorState: state,
              blockComponentBuilders: builderMap(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('equationBlockNode carries the attribute shape', () {
    final node = equationBlockNode(latex: r'\frac{a}{b}');
    expect(node.type, kEquationBlockType);
    expect(node.attributes[kEquationBlockLatexKey], r'\frac{a}{b}');
  });

  test('equation node round-trips through document JSON', () {
    final state = editorWith(equationBlockNode(latex: r'e^{i\pi}+1=0'));
    final json = state.document.toJson();
    final restored = EditorState(document: Document.fromJson(json));
    final node = restored.document.root.children[1];
    expect(node.type, kEquationBlockType);
    expect(node.attributes[kEquationBlockLatexKey], r'e^{i\pi}+1=0');
  });

  testWidgets('equation block renders without crashing', (tester) async {
    final state = editorWith(equationBlockNode(latex: r'\frac{a}{b}+c^2'));
    await pumpEditor(tester, state);
    await tester.pumpAndSettle();
    expect(find.byType(RichText), findsWidgets);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('malformed LaTeX shows error fallback', (tester) async {
    final state = editorWith(equationBlockNode(latex: r'\frac{'));
    await pumpEditor(tester, state);
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('blank LaTeX shows placeholder line', (tester) async {
    final state = editorWith(equationBlockNode(latex: ''));
    await pumpEditor(tester, state);
    await tester.pumpAndSettle();
    expect(find.textContaining('Equation is blank'), findsOneWidget);
  });
}
