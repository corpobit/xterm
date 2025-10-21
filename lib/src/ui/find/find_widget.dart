import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/ui/find/find_controller.dart';
import 'package:xterm/src/ui/terminal_theme.dart';

/// A find widget that appears as an overlay in the terminal.
class FindWidget extends StatefulWidget {
  const FindWidget({
    super.key,
    required this.controller,
    required this.theme,
    required this.textStyle,
  });

  final FindController controller;
  final TerminalTheme theme;
  final TextStyle textStyle;

  @override
  State<FindWidget> createState() => _FindWidgetState();
}

class _FindWidgetState extends State<FindWidget> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _hasAutoFocused = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    
    // Listen to controller changes
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {
        // Update text controller if search text changed externally
        if (_textController.text != widget.controller.searchText) {
          _textController.text = widget.controller.searchText;
        }
      });
      
      // Auto-focus only when find dialog first becomes visible
      if (widget.controller.isVisible && !_focusNode.hasFocus && !_hasAutoFocused) {
        _hasAutoFocused = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
      
      // Reset auto-focus flag when dialog is hidden
      if (!widget.controller.isVisible) {
        _hasAutoFocused = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isVisible) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: widget.theme.background,
        shadowColor: Colors.black.withOpacity(0.3),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 320,
            maxWidth: 480,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.theme.cursor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: _buildCompactSearchBar(),
        ),
      ),
    );
  }

  Widget _buildCompactSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Search icon
          Icon(
            Icons.search,
            size: 18,
            color: widget.theme.foreground.withOpacity(0.6),
          ),
          const SizedBox(width: 8),
          
          // Search input with integrated controls
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  final isFindShortcut = (HardwareKeyboard.instance.isControlPressed && 
                                         event.logicalKey == LogicalKeyboardKey.keyF) ||
                                        (HardwareKeyboard.instance.isMetaPressed && 
                                         event.logicalKey == LogicalKeyboardKey.keyF);
                  
                  if (isFindShortcut) {
                    widget.controller.toggle();
                    return;
                  }
                  
                  // Handle Escape key to close
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.controller.hide();
                    return;
                  }
                }
              },
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: widget.textStyle.copyWith(
                  color: widget.theme.foreground,
                ),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: widget.textStyle.copyWith(
                    color: widget.theme.foreground.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // Result count
                    if (widget.controller.resultCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: widget.theme.cursor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.controller.currentResultIndex + 1}/${widget.controller.resultCount}',
                          style: widget.textStyle.copyWith(
                            color: widget.theme.foreground,
                            fontSize: widget.textStyle.fontSize! * 0.85,
                          ),
                        ),
                      ),
                    
                    // Case sensitive toggle
                    _buildIconToggle(
                      icon: Icons.text_format,
                      isActive: widget.controller.caseSensitive,
                      onTap: () => widget.controller.setCaseSensitive(!widget.controller.caseSensitive),
                    ),
                    
                    // Whole word toggle
                    _buildIconToggle(
                      icon: Icons.text_fields,
                      isActive: widget.controller.wholeWord,
                      onTap: () => widget.controller.setWholeWord(!widget.controller.wholeWord),
                    ),
                    
                    // Regex toggle
                    _buildIconToggle(
                      icon: Icons.code,
                      isActive: widget.controller.regex,
                      onTap: () => widget.controller.setRegex(!widget.controller.regex),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Previous button
                    _buildIconButton(
                      icon: Icons.keyboard_arrow_up,
                      onTap: widget.controller.findPrevious,
                      enabled: widget.controller.resultCount > 0,
                    ),
                    
                    // Next button
                    _buildIconButton(
                      icon: Icons.keyboard_arrow_down,
                      onTap: widget.controller.findNext,
                      enabled: widget.controller.resultCount > 0,
                    ),
                    
                    const SizedBox(width: 4),
                    
                    // Close button
                    _buildIconButton(
                      icon: Icons.close,
                      onTap: widget.controller.hide,
                    ),
                  ],
                ),
              ),
              onChanged: (value) {
                widget.controller.setSearchText(value);
              },
              onSubmitted: (value) {
                widget.controller.findNext();
              },
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconToggle({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive 
            ? widget.theme.cursor.withOpacity(0.2)
            : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isActive 
            ? widget.theme.cursor
            : widget.theme.foreground.withOpacity(0.6),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 16,
          color: enabled 
            ? widget.theme.foreground.withOpacity(0.8)
            : widget.theme.foreground.withOpacity(0.3),
        ),
      ),
    );
  }




}
