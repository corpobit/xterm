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
        final cursorOffset = renderTerminal.cursorOffset;
        final isLoading = controller.isLoading;
        final hasCompletions = controller.hasCompletions;
        
        // Check if current line is empty (no user input)
        final buffer = controller.terminal.buffer;
        final currentLine = buffer.currentLine;
        final cursorX = buffer.cursorX;
        final lineText = currentLine.getText(0, cursorX);
        
        // Extract user input by removing prompt to check if line is truly empty
        final userInput = _extractUserInputFromLine(lineText);
        final isLineEmpty = userInput.trim().isEmpty;
        
        // Show loading indicator when fetching
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
        
        // Show placeholder when line is empty
        if (isLineEmpty && !hasCompletions) {
          return Positioned(
            left: cursorOffset.dx,
            top: cursorOffset.dy,
            child: _PlaceholderText(
              theme: theme,
              textStyle: textStyle,
            ),
          );
        }
        
        // Show completions when available
        if (!hasCompletions) {
          return const SizedBox.shrink();
        }

        final completions = controller.completions;
        final selectedIndex = controller.selectedIndex;
        final currentCompletionRemainder = controller.currentCompletionRemainder;

        if (currentCompletionRemainder == null || currentCompletionRemainder.isEmpty) {
          return const SizedBox.shrink();
        }
        
        // Position the autocomplete inline at the cursor position (same line, after cursor)
        return Positioned(
          left: cursorOffset.dx,
          top: cursorOffset.dy,
          child: _AutocompleteOverlay(
            completions: completions,
            selectedIndex: selectedIndex,
            currentCompletionRemainder: currentCompletionRemainder,
            theme: theme,
            textStyle: textStyle,
          ),
        );
      },
    );
  }
  
  /// Extract user input from line text by removing prompt patterns
  /// (Same logic as AutocompleteController._extractUserInput)
  String _extractUserInputFromLine(String lineText) {
    int promptEnd = -1;
    
    // Pattern 1: Look for % $ # > followed by space (most common)
    final promptMarkerPattern = RegExp(r'[%$#>]\s+');
    final markerMatches = promptMarkerPattern.allMatches(lineText);
    if (markerMatches.isNotEmpty) {
      promptEnd = markerMatches.last.end;
    }
    
    // Pattern 2: Look for user@host pattern followed by space or colon+space
    if (promptEnd == -1) {
      final userHostPattern = RegExp(r'\w+@[\w\-\.]+[:\s]+');
      final userHostMatches = userHostPattern.allMatches(lineText);
      if (userHostMatches.isNotEmpty) {
        for (final match in userHostMatches) {
          final end = match.end;
          if (end < lineText.length) {
            final afterMatch = lineText.substring(end);
            final markerMatch = promptMarkerPattern.firstMatch(afterMatch);
            if (markerMatch != null) {
              promptEnd = end + markerMatch.end;
              break;
            }
          }
        }
      }
    }
    
    // Extract user input after prompt
    if (promptEnd > 0 && promptEnd < lineText.length) {
      return lineText.substring(promptEnd);
    }
    
    return lineText;
  }
}

class _AutocompleteOverlay extends StatelessWidget {
  final List<String> completions;
  final int selectedIndex;
  final String currentCompletionRemainder;
  final TerminalTheme theme;
  final TerminalStyle textStyle;

  const _AutocompleteOverlay({
    required this.completions,
    required this.selectedIndex,
    required this.currentCompletionRemainder,
    required this.theme,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    // Display only the remaining part (difference) of the completion
    // Show index indicator next to it
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only show the remaining part with transparent color (like normal terminal text)
        Text(
          currentCompletionRemainder,
          style: textStyle.toTextStyle().copyWith(
            color: theme.foreground.withOpacity(0.5),
          ),
        ),
        const SizedBox(width: 8),
        // Index indicator
        Text(
          '${selectedIndex + 1}/${completions.length}',
          style: textStyle.toTextStyle().copyWith(
            color: theme.foreground.withOpacity(0.7),
            fontSize: textStyle.fontSize * 0.9,
          ),
        ),
      ],
    );
  }
}

class _PlaceholderText extends StatelessWidget {
  final TerminalTheme theme;
  final TerminalStyle textStyle;

  const _PlaceholderText({
    required this.theme,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      'Type a part of the command and let AI bring the rest',
      style: textStyle.toTextStyle().copyWith(
        color: theme.foreground.withOpacity(0.4),
        fontStyle: FontStyle.italic,
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

