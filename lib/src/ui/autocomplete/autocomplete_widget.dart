import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:xterm/src/ui/autocomplete/autocomplete_controller.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/terminal_theme.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';

class AutocompleteWidget extends StatelessWidget {
  final AutocompleteController controller;
  final RenderTerminal renderTerminal;
  final TerminalTheme theme;
  final TerminalStyle textStyle;

  const AutocompleteWidget({
    super.key,
    required this.controller,
    required this.renderTerminal,
    required this.theme,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        try {
          final buffer = controller.terminal.buffer;
          final currentLine = buffer.currentLine;
          final cursorX = buffer.cursorX;
          final lineText = currentLine.getText(0, cursorX);
          final userInput = controller.extractUserInput(lineText);
          final trimmed = userInput.trim();
          
          if (trimmed.isEmpty) {
            Future.microtask(() {
              if (controller.hasCompletions) {
                controller.clear();
              }
            });
            return const SizedBox.shrink();
          }
        } catch (e) {
          return const SizedBox.shrink();
        }
        
        if (!controller.hasValidInput) {
          Future.microtask(() {
            if (controller.hasCompletions) {
              controller.clear();
            }
          });
          return const SizedBox.shrink();
        }
        
        final cursorOffset = renderTerminal.cursorOffset;
        final isLoading = controller.isLoading;
        final hasCompletions = controller.hasCompletions;
        final isLoadingAgent = controller.isLoadingAgent;
        
        // Agent response is now written directly to terminal as ANSI-formatted text
        // No need to show overlay widget
        
        // Show loading indicator when fetching agent response
        if (isLoadingAgent) {
          final lineHeight = renderTerminal.lineHeight;
          final loadingTop = cursorOffset.dy + lineHeight;
          // Position at the beginning of the line (accounting for line numbers if present)
          const double lineNumberWidth = 40.0; // Match the line number width in render.dart
          final loadingLeft = lineNumberWidth; // Start after line number area
          
          return Positioned(
            left: loadingLeft,
            top: loadingTop,
            child: _LoadingIndicator(
              theme: theme,
              textStyle: textStyle,
            ),
          );
        }
        
        // Show loading indicator when fetching autocomplete
        if (isLoading) {
          return Positioned(
            left: cursorOffset.dx,
            top: cursorOffset.dy,
            child: _LoadingIndicator(
              theme: theme,
              textStyle: textStyle,
            ),
          );
        }
        
        // Show completions when available and there's a valid remainder
        if (!hasCompletions) {
          return const SizedBox.shrink();
        }

        final completions = controller.completions;
        final selectedIndex = controller.selectedIndex;
        final currentCompletionRemainder = controller.currentCompletionRemainder;
        
        // Only show menu if there's a valid remainder (menu should be visible)
        if (currentCompletionRemainder == null || currentCompletionRemainder.isEmpty) {
          return const SizedBox.shrink();
        }
        
        final lineHeight = renderTerminal.lineHeight;
        
        // Position the autocomplete menu below the cursor
        return Positioned(
          left: cursorOffset.dx,
          top: cursorOffset.dy + lineHeight,
          child: _AutocompleteMenu(
            completions: completions,
            selectedIndex: selectedIndex,
            theme: theme,
            textStyle: textStyle,
          ),
        );
      },
    );
  }
}

class _AutocompleteMenu extends StatefulWidget {
  final List<String> completions;
  final int selectedIndex;
  final TerminalTheme theme;
  final TerminalStyle textStyle;

  const _AutocompleteMenu({
    required this.completions,
    required this.selectedIndex,
    required this.theme,
    required this.textStyle,
  });

  @override
  State<_AutocompleteMenu> createState() => _AutocompleteMenuState();
}

class _AutocompleteMenuState extends State<_AutocompleteMenu> {
  late ScrollController _scrollController;
  int _lastSelectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _lastSelectedIndex = widget.selectedIndex;
  }

  @override
  void didUpdateWidget(_AutocompleteMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Scroll to selected item when selection changes
    if (widget.selectedIndex != _lastSelectedIndex) {
      _lastSelectedIndex = widget.selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    
    final lineHeight = widget.textStyle.fontSize * 1.2;
    final itemHeight = lineHeight * 1.5;
    const maxVisibleItems = 8;
    final selectedOffset = widget.selectedIndex * itemHeight;
    final viewportHeight = maxVisibleItems * itemHeight;
    
    // Calculate scroll position to center the selected item in viewport
    final targetOffset = (selectedOffset - viewportHeight / 2 + itemHeight / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineHeight = widget.textStyle.fontSize * 1.2;
    final maxHeight = lineHeight * 8; // Show max 8 items, then scroll
    final itemHeight = lineHeight * 1.8; // Increased height to prevent overflow
    
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
        minWidth: 250,
        maxWidth: 600,
      ),
      child: Material(
        color: widget.theme.background,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: widget.theme.background,
            border: Border.all(
              color: widget.theme.foreground.withOpacity(0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              physics: const ClampingScrollPhysics(),
              itemCount: widget.completions.length,
              itemBuilder: (context, index) {
                final isSelected = index == widget.selectedIndex;
                
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  height: itemHeight,
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? widget.theme.foreground.withOpacity(0.15)
                        : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: isSelected 
                            ? widget.theme.foreground.withOpacity(0.6)
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: null, // Handled by keyboard
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Selection indicator
                            if (isSelected)
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: widget.theme.foreground,
                                  shape: BoxShape.circle,
                                ),
                              )
                            else
                              const SizedBox(width: 16),
                            // Text content
                            Flexible(
                              child: Text(
                                widget.completions[index],
                                style: widget.textStyle.toTextStyle().copyWith(
                                  color: isSelected
                                      ? widget.theme.foreground
                                      : widget.theme.foreground.withOpacity(0.85),
                                  fontWeight: isSelected 
                                      ? FontWeight.w600 
                                      : FontWeight.normal,
                                  fontSize: widget.textStyle.fontSize * 0.95,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Index indicator for selected item
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.theme.foreground.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: widget.textStyle.toTextStyle().copyWith(
                                      color: widget.theme.foreground,
                                      fontSize: widget.textStyle.fontSize * 0.75,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingIndicator extends StatefulWidget {
  final TerminalTheme theme;
  final TerminalStyle textStyle;

  const _LoadingIndicator({
    required this.theme,
    required this.textStyle,
  });

  @override
  State<_LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Create dancing dots with different vertical offsets
        final cellHeight = widget.textStyle.fontSize * 1.2;
        final dot1Offset = (math.sin(_controller.value * 2 * math.pi) * cellHeight * 0.15);
        final dot2Offset = (math.sin(_controller.value * 2 * math.pi + math.pi * 2 / 3) * cellHeight * 0.15);
        final dot3Offset = (math.sin(_controller.value * 2 * math.pi + math.pi * 4 / 3) * cellHeight * 0.15);
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, dot1Offset),
              child: Text(
                '.',
                style: widget.textStyle.toTextStyle().copyWith(
                  color: widget.theme.foreground.withOpacity(0.5),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, dot2Offset),
              child: Text(
                '.',
                style: widget.textStyle.toTextStyle().copyWith(
                  color: widget.theme.foreground.withOpacity(0.5),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, dot3Offset),
              child: Text(
                '.',
                style: widget.textStyle.toTextStyle().copyWith(
                  color: widget.theme.foreground.withOpacity(0.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
