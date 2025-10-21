import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Map<ShortcutActivator, Intent> get defaultTerminalShortcuts {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return _defaultShortcuts;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _defaultAppleShortcuts;
  }
}

final _defaultShortcuts = {
  // Note: Ctrl+C is intentionally excluded to allow terminal interrupt signal
  SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, control: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};

final _defaultAppleShortcuts = {
  // Note: Cmd+C is intentionally excluded to allow terminal interrupt signal
  SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};
