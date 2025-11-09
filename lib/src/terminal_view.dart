import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/selection_mode.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/src/ui/gesture/gesture_handler.dart';
import 'package:xterm/src/ui/input_map.dart';
import 'package:xterm/src/ui/keyboard_listener.dart';
import 'package:xterm/src/ui/keyboard_visibility.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/scroll_handler.dart';
import 'package:xterm/src/ui/shortcut/actions.dart';
import 'package:xterm/src/ui/shortcut/shortcuts.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';
import 'package:xterm/src/ui/themes.dart';
import 'package:xterm/src/ui/find/find_controller.dart';
import 'package:xterm/src/ui/find/find_widget.dart';
import 'package:xterm/src/ui/buffer_usage_indicator.dart';

class TerminalView extends StatefulWidget {
  const TerminalView(
    this.terminal, {
    super.key,
    this.controller,
    this.theme = TerminalThemes.defaultTheme,
    this.textStyle = const TerminalStyle(),
    this.textScaler,
    this.padding,
    this.scrollController,
    this.autoResize = true,
    this.backgroundOpacity = 1,
    this.focusNode,
    this.autofocus = false,
    this.onTapUp,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.mouseCursor = SystemMouseCursors.text,
    this.keyboardType = TextInputType.emailAddress,
    this.keyboardAppearance = Brightness.dark,
    this.cursorType = TerminalCursorType.block,
    this.alwaysShowCursor = false,
    this.showLineNumbers = true,
    this.showMinimap = false,
    this.showBufferIndicator = true,
    this.bookmarks = const {},
    this.bookmarkNames = const {},
    this.onBookmarkToggle,
    this.onJumpToBookmark,
    this.activeBookmarkLine,
    this.deleteDetection = false,
    this.shortcuts,
    this.onKeyEvent,
    this.readOnly = false,
    this.hardwareKeyboardOnly = false,
    this.simulateScroll = true,
  });

  /// Global key to access the TerminalViewState methods
  static GlobalKey<TerminalViewState> createGlobalKey() {
    return GlobalKey<TerminalViewState>();
  }

  /// The underlying terminal that this widget renders.
  final Terminal terminal;

  final TerminalController? controller;

  /// The theme to use for this terminal.
  final TerminalTheme theme;

  /// The style to use for painting characters.
  final TerminalStyle textStyle;

  final TextScaler? textScaler;

  /// Padding around the inner [Scrollable] widget.
  final EdgeInsets? padding;

  /// Scroll controller for the inner [Scrollable] widget.
  final ScrollController? scrollController;

  /// Should this widget automatically notify the underlying terminal when its
  /// size changes. [true] by default.
  final bool autoResize;

  /// Opacity of the terminal background. Set to 0 to make the terminal
  /// background transparent.
  final double backgroundOpacity;

  /// An optional focus node to use as the focus node for this widget.
  final FocusNode? focusNode;

  /// True if this widget will be selected as the initial focus when no other
  /// node in its scope is currently focused.
  final bool autofocus;

  /// Callback for when the user taps on the terminal.
  final void Function(TapUpDetails, CellOffset)? onTapUp;

  /// Function called when the user taps on the terminal with a secondary
  /// button.
  final void Function(TapDownDetails, CellOffset)? onSecondaryTapDown;

  /// Function called when the user stops holding down a secondary button.
  final void Function(TapUpDetails, CellOffset)? onSecondaryTapUp;

  /// The mouse cursor for mouse pointers that are hovering over the terminal.
  /// [SystemMouseCursors.text] by default.
  final MouseCursor mouseCursor;

  /// The type of information for which to optimize the text input control.
  /// [TextInputType.emailAddress] by default.
  final TextInputType keyboardType;

  /// The appearance of the keyboard. [Brightness.dark] by default.
  ///
  /// This setting is only honored on iOS devices.
  final Brightness keyboardAppearance;

  /// The type of cursor to use. [TerminalCursorType.block] by default.
  final TerminalCursorType cursorType;

  /// Whether to always show the cursor. This is useful for debugging.
  /// [false] by default.
  final bool alwaysShowCursor;

  /// Whether to show line numbers in the terminal. [true] by default.
  final bool showLineNumbers;

  /// Whether to show a minimap in the terminal. [false] by default.
  final bool showMinimap;

  /// Whether to show the buffer usage indicator. [true] by default.
  final bool showBufferIndicator;

  /// Set of bookmarked line numbers
  final Set<int> bookmarks;

  /// Map of bookmark names for each line
  final Map<int, String> bookmarkNames;

  /// Callback when a bookmark is toggled
  final Function(int)? onBookmarkToggle;

  /// Callback when jumping to a bookmark
  final Function(int)? onJumpToBookmark;

  /// The currently active bookmark line (highlighted)
  final int? activeBookmarkLine;

  /// Workaround to detect delete key for platforms and IMEs that does not
  /// emit hardware delete event. Prefered on mobile platforms. [false] by
  /// default.
  final bool deleteDetection;

  /// Shortcuts for this terminal. This has higher priority than input handler
  /// of the terminal If not provided, [defaultTerminalShortcuts] will be used.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Keyboard event handler of the terminal. This has higher priority than
  /// [shortcuts] and input handler of the terminal.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// True if no input should send to the terminal.
  final bool readOnly;

  /// True if only hardware keyboard events should be used as input. This will
  /// also prevent any on-screen keyboard to be shown.
  final bool hardwareKeyboardOnly;

  /// If true, when the terminal is in alternate buffer (for example running
  /// vim, man, etc), if the application does not declare that it can handle
  /// scrolling, the terminal will simulate scrolling by sending up/down arrow
  /// keys to the application. This is standard behavior for most terminal
  /// emulators. True by default.
  final bool simulateScroll;

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView>
    with AutomaticKeepAliveClientMixin {
  late FocusNode _focusNode;

  late final ShortcutManager _shortcutManager;

  final _customTextEditKey = GlobalKey<CustomTextEditState>();

  final _scrollableKey = GlobalKey<ScrollableState>();

  final _viewportKey = GlobalKey();

  String? _composingText;

  late TerminalController _controller;

  late ScrollController _scrollController;

  late FindController _findController;

  MouseCursor _currentCursor = SystemMouseCursors.text;
  int? _hoveredLineNumber;

  RenderTerminal get renderTerminal =>
      _viewportKey.currentContext!.findRenderObject() as RenderTerminal;

  /// Scroll to a specific line number
  void scrollToLine(int lineNumber) {
    if (lineNumber < 0) return;

    // Calculate the pixel offset for the line
    final lineHeight = renderTerminal.lineHeight;
    final targetOffset = lineNumber * lineHeight;

    // Get the viewport height to calculate center position
    final viewportHeight = _scrollController.position.viewportDimension;
    final linesInViewport = viewportHeight / lineHeight;

    // Position the line in the middle of the viewport (with some padding)
    final centerOffset = (linesInViewport / 2) * lineHeight;
    final adjustedOffset = (targetOffset - centerOffset)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    // Scroll to the target line
    _scrollController.animateTo(
      adjustedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Scroll to a specific match in the terminal
  void _scrollToMatch(CellOffset matchOffset) {
    // Calculate the pixel offset for the match
    final lineHeight = renderTerminal.lineHeight;
    final targetOffset = matchOffset.y * lineHeight;

    // Get the viewport height to calculate center position
    final viewportHeight = _scrollController.position.viewportDimension;
    final linesInViewport = viewportHeight / lineHeight;

    // Position the match in the middle of the viewport (with some padding)
    final centerOffset = (linesInViewport / 2) * lineHeight;
    final adjustedOffset = (targetOffset - centerOffset)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    // Scroll to the target match
    _scrollController.animateTo(
      adjustedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TerminalController();
    _scrollController = widget.scrollController ?? ScrollController();
    _findController = FindController(
      terminal: widget.terminal,
      controller: _controller,
      theme: widget.theme,
    );
    _findController.onScrollToMatch = _scrollToMatch;
    _shortcutManager = ShortcutManager(
      shortcuts: widget.shortcuts ?? defaultTerminalShortcuts,
    );
    super.initState();
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _controller.dispose();
      }
      _controller = widget.controller ?? TerminalController();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
    }
    _shortcutManager.shortcuts = widget.shortcuts ?? defaultTerminalShortcuts;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _findController.dispose();
    _shortcutManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget child = Scrollable(
      key: _scrollableKey,
      controller: _scrollController,
      viewportBuilder: (context, offset) {
        return _TerminalView(
          key: _viewportKey,
          terminal: widget.terminal,
          controller: _controller,
          offset: offset,
          padding: MediaQuery.of(context).padding,
          autoResize: widget.autoResize,
          textStyle: widget.textStyle,
          textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
          theme: widget.theme,
          focusNode: _focusNode,
          cursorType: widget.cursorType,
          alwaysShowCursor: widget.alwaysShowCursor,
          showLineNumbers: widget.showLineNumbers,
          showMinimap: widget.showMinimap,
          showBufferIndicator: widget.showBufferIndicator,
          bookmarks: widget.bookmarks,
          bookmarkNames: widget.bookmarkNames,
          onBookmarkToggle: widget.onBookmarkToggle,
          onJumpToBookmark: widget.onJumpToBookmark,
          activeBookmarkLine: widget.activeBookmarkLine,
          hoveredLineNumber: _hoveredLineNumber,
          onEditableRect: _onEditableRect,
          composingText: _composingText,
        );
      },
    );

    child = TerminalScrollGestureHandler(
      terminal: widget.terminal,
      simulateScroll: widget.simulateScroll,
      getCellOffset: (offset) => renderTerminal.getCellOffset(offset),
      getLineHeight: () => renderTerminal.lineHeight,
      child: child,
    );

    if (!widget.hardwareKeyboardOnly) {
      child = CustomTextEdit(
        key: _customTextEditKey,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        inputType: widget.keyboardType,
        keyboardAppearance: widget.keyboardAppearance,
        deleteDetection: widget.deleteDetection,
        onInsert: _onInsert,
        onDelete: () {
          _scrollToBottom();
          widget.terminal.keyInput(TerminalKey.backspace);
        },
        onComposing: _onComposing,
        onAction: (action) {
          _scrollToBottom();
          // Android sends TextInputAction.newline when the user presses the virtual keyboard's enter key.
          if (action == TextInputAction.done ||
              action == TextInputAction.newline) {
            widget.terminal.keyInput(TerminalKey.enter);
          }
        },
        onKeyEvent: _handleKeyEvent,
        readOnly: widget.readOnly,
        child: child,
      );
    } else if (!widget.readOnly) {
      // Only listen for key input from a hardware keyboard.
      child = CustomKeyboardListener(
        child: child,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onInsert: _onInsert,
        onComposing: _onComposing,
        onKeyEvent: _handleKeyEvent,
      );
    }

    child = TerminalActions(
      terminal: widget.terminal,
      controller: _controller,
      findController: _findController,
      child: child,
    );

    child = KeyboardVisibilty(
      onKeyboardShow: _onKeyboardShow,
      child: child,
    );

    child = TerminalGestureHandler(
      terminalView: this,
      terminalController: _controller,
      onTapUp: _onTapUp,
      onTapDown: _onTapDown,
      onSecondaryTapDown:
          widget.onSecondaryTapDown != null ? _onSecondaryTapDown : null,
      onSecondaryTapUp:
          widget.onSecondaryTapUp != null ? _onSecondaryTapUp : null,
      readOnly: widget.readOnly,
      child: child,
    );

    // Add minimap gesture detection if minimap is enabled
    if (widget.showMinimap) {
      child = GestureDetector(
        onTapDown: _onMinimapTap,
        onPanStart: _onMinimapPanStart,
        onPanUpdate: _onMinimapDrag,
        onPanEnd: _onMinimapPanEnd,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    // Add line number gesture detection if line numbers are enabled
    if (widget.showLineNumbers) {
      child = GestureDetector(
        onTapDown: _onLineNumberTap,
        onTapUp: _onLineNumberTapUp,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    // Add mouse region for cursor change
    child = MouseRegion(
      onHover: (event) {
        try {
          final renderTerminal = this.renderTerminal;
          final cursor =
              renderTerminal.getCursorForPosition(event.localPosition);
          if (_currentCursor != cursor) {
            setState(() {
              _currentCursor = cursor;
            });
          }

          // Track line number hover
          if (widget.showLineNumbers) {
            final hoveredLine =
                renderTerminal.getHoveredLineNumber(event.localPosition);
            if (_hoveredLineNumber != hoveredLine) {
              setState(() {
                _hoveredLineNumber = hoveredLine;
              });
            }
          }

          // Handle minimap hover for scroll navigation
          if (widget.showMinimap) {
            renderTerminal.handleMinimapInteraction(event.localPosition);
          }
        } catch (e) {
          // Ignore errors
        }
      },
      onExit: (event) {
        if (_hoveredLineNumber != null) {
          setState(() {
            _hoveredLineNumber = null;
          });
        }
      },
      cursor: _currentCursor,
      child: child,
    );

    child = Container(
      color: widget.theme.background.withOpacity(widget.backgroundOpacity),
      padding: widget.padding,
      child: child,
    );

    // Add find widget and buffer usage indicator as overlays
    child = Stack(
      children: [
        child,
        FindWidget(
          controller: _findController,
          theme: widget.theme,
          textStyle: widget.textStyle.toTextStyle(),
        ),
        if (widget.showBufferIndicator)
          BufferUsageIndicator(
            terminal: widget.terminal,
            theme: widget.theme,
            textStyle: widget.textStyle.toTextStyle(),
          ),
      ],
    );

    return child;
  }

  void requestKeyboard() {
    _customTextEditKey.currentState?.requestKeyboard();
  }

  void closeKeyboard() {
    _customTextEditKey.currentState?.closeKeyboard();
  }

  Rect get cursorRect {
    return renderTerminal.cursorOffset & renderTerminal.cellSize;
  }

  Rect get globalCursorRect {
    return renderTerminal.localToGlobal(renderTerminal.cursorOffset) &
        renderTerminal.cellSize;
  }

  void _onTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onTapUp?.call(details, offset);
  }

  void _onTapDown(_) {
    if (_controller.selection != null) {
      _controller.clearSelection();
    } else {
      if (!widget.hardwareKeyboardOnly) {
        _customTextEditKey.currentState?.requestKeyboard();
      } else {
        _focusNode.requestFocus();
      }
    }
  }

  void _onSecondaryTapDown(TapDownDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapDown?.call(details, offset);
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapUp?.call(details, offset);
  }

  void _onMinimapTap(TapDownDetails details) {
    renderTerminal.handleMinimapInteraction(details.localPosition,
        isDragging: false);
  }

  void _onMinimapPanStart(DragStartDetails details) {
    renderTerminal.handleMinimapInteraction(details.localPosition,
        isDragging: true);
  }

  void _onMinimapDrag(DragUpdateDetails details) {
    renderTerminal.handleMinimapInteraction(details.localPosition,
        isDragging: true);
  }

  void _onMinimapPanEnd(DragEndDetails details) {
    renderTerminal.handleMinimapInteraction(details.localPosition,
        isDragging: false);
  }

  void _onLineNumberTap(TapDownDetails details) {
    renderTerminal.handleLineNumberClick(details.localPosition);
  }

  void _onLineNumberTapUp(TapUpDetails details) {
    renderTerminal.handleLineNumberClick(details.localPosition);
  }

  bool get hasInputConnection {
    return _customTextEditKey.currentState?.hasInputConnection == true;
  }

  void _onInsert(String text) {
    final key = charToTerminalKey(text.trim());

    // On mobile platforms there is no guarantee that virtual keyboard will
    // generate hardware key events. So we need first try to send the key
    // as a hardware key event. If it fails, then we send it as a text input.
    final consumed = key == null ? false : widget.terminal.keyInput(key);

    if (!consumed) {
      widget.terminal.textInput(text);
    }

    _scrollToBottom();
  }

  void _onComposing(String? text) {
    setState(() => _composingText = text);
  }

  KeyEventResult _handleKeyEvent(FocusNode focusNode, KeyEvent event) {
    // 1. External override
    final resultOverride = widget.onKeyEvent?.call(focusNode, event);
    if (resultOverride != null && resultOverride != KeyEventResult.ignored) {
      return resultOverride;
    }

    // 2. Find: Ctrl/Cmd + F
    if (event is KeyDownEvent) {
      final isFind = (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyF;
      if (isFind) {
        _findController.toggle();
        return KeyEventResult.handled;
      }
    }

    // 3. Copy/Paste: Ctrl/Cmd + A, V
    if (event is KeyDownEvent) {
      final isMod = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (isMod) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyA:
            _selectAllText();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyV:
            _pasteFromClipboard();
            return KeyEventResult.handled;
        }
      }
    }

    // 4. Built-in shortcuts
    final shortcutResult =
        _shortcutManager.handleKeypress(focusNode.context!, event);
    if (shortcutResult != KeyEventResult.ignored) {
      return shortcutResult;
    }

    // 5. Ignore KeyUp early
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }


    // 7. ALL OTHER KEYS
    final key = keyToTerminalKey(event.logicalKey);
    if (key == null) {
      return KeyEventResult.ignored;
    }

    final handled = widget.terminal.keyInput(
      key,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );

    if (handled) {
      _scrollToBottom();
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }



  void _onKeyboardShow() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _onEditableRect(Rect rect, Rect caretRect) {
    _customTextEditKey.currentState?.setEditableRect(rect, caretRect);
  }

  void _scrollToBottom() {
    final position = _scrollableKey.currentState?.position;
    if (position != null) {
      position.jumpTo(position.maxScrollExtent);
    }
  }

  /// Reset the find state (useful when terminal buffer is cleared)
  void resetFindState() {
    _findController.resetFindState();
  }

  /// Select all text in the terminal
  void _selectAllText() {
    final buffer = widget.terminal.buffer;
    if (buffer.lines.length == 0) return;

    _controller.setSelection(
      buffer.createAnchor(0, buffer.height - buffer.viewHeight),
      buffer.createAnchor(buffer.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  /// Copy selected text to clipboard
  void _copySelectedText() {
    final selection = _controller.selection;
    if (selection == null) return;

    final selectedText = widget.terminal.buffer.getText(selection);
    if (selectedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selectedText));
    }
  }

  /// Paste text from clipboard
  void _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
      // Use the terminal's paste method
      widget.terminal.paste(clipboardData.text!);
      _controller.clearSelection();
      _scrollToBottom();
    }
  }

  @override
  bool get wantKeepAlive => true;
}

class _TerminalView extends LeafRenderObjectWidget {
  const _TerminalView({
    super.key,
    required this.terminal,
    required this.controller,
    required this.offset,
    required this.padding,
    required this.autoResize,
    required this.textStyle,
    required this.textScaler,
    required this.theme,
    required this.focusNode,
    required this.cursorType,
    required this.alwaysShowCursor,
    required this.showLineNumbers,
    required this.showMinimap,
    required this.showBufferIndicator,
    required this.bookmarks,
    required this.bookmarkNames,
    required this.onBookmarkToggle,
    required this.onJumpToBookmark,
    this.activeBookmarkLine,
    this.hoveredLineNumber,
    this.onEditableRect,
    this.composingText,
  });

  final Terminal terminal;

  final TerminalController controller;

  final ViewportOffset offset;

  final EdgeInsets padding;

  final bool autoResize;

  final TerminalStyle textStyle;

  final TextScaler textScaler;

  final TerminalTheme theme;

  final FocusNode focusNode;

  final TerminalCursorType cursorType;

  final bool alwaysShowCursor;

  final bool showLineNumbers;

  final bool showMinimap;

  final bool showBufferIndicator;

  final Set<int> bookmarks;

  final Map<int, String> bookmarkNames;

  final Function(int)? onBookmarkToggle;

  final Function(int)? onJumpToBookmark;

  final int? activeBookmarkLine;

  final int? hoveredLineNumber;

  final EditableRectCallback? onEditableRect;

  final String? composingText;

  @override
  RenderTerminal createRenderObject(BuildContext context) {
    return RenderTerminal(
      terminal: terminal,
      controller: controller,
      offset: offset,
      padding: padding,
      autoResize: autoResize,
      textStyle: textStyle,
      textScaler: textScaler,
      theme: theme,
      focusNode: focusNode,
      cursorType: cursorType,
      alwaysShowCursor: alwaysShowCursor,
      onEditableRect: onEditableRect,
      composingText: composingText,
      showLineNumbers: showLineNumbers,
      showMinimap: showMinimap,
      bookmarks: bookmarks,
      bookmarkNames: bookmarkNames,
      onBookmarkToggle: onBookmarkToggle,
      onJumpToBookmark: onJumpToBookmark,
      activeBookmarkLine: activeBookmarkLine,
      hoveredLineNumber: hoveredLineNumber,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderTerminal renderObject) {
    renderObject
      ..terminal = terminal
      ..controller = controller
      ..offset = offset
      ..padding = padding
      ..autoResize = autoResize
      ..textStyle = textStyle
      ..textScaler = textScaler
      ..theme = theme
      ..focusNode = focusNode
      ..cursorType = cursorType
      ..alwaysShowCursor = alwaysShowCursor
      ..onEditableRect = onEditableRect
      ..composingText = composingText
      ..showLineNumbers = showLineNumbers
      ..showMinimap = showMinimap
      ..bookmarks = bookmarks
      ..bookmarkNames = bookmarkNames
      ..onBookmarkToggle = onBookmarkToggle
      ..onJumpToBookmark = onJumpToBookmark
      ..activeBookmarkLine = activeBookmarkLine
      ..hoveredLineNumber = hoveredLineNumber;
  }
}
