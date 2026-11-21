/// Shared keyboard-navigation primitives for browse surfaces.
///
/// Composition layer (intents/actions + selection controllers + a focus-aware
/// scope). Not a base widget; pages wire their own data/activation. Deliberately
/// separate from editor modal vim (`features/editor/helpers/`) and reader key
/// handling (`features/reader/reader.dart`).
library;

export 'grid_nav_controller.dart';
export 'keyboard_nav_scope.dart';
export 'linear_nav_controller.dart';
export 'nav_intents.dart';
