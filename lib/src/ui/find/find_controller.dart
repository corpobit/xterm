import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/terminal_theme.dart';

/// Controller for managing the find functionality in the terminal.
class FindController extends ChangeNotifier {
  FindController({required this.terminal, required this.controller, required this.theme}) {
    // Listen to terminal changes for auto-updating search results
    terminal.addListener(_onTerminalChange);
  }

  final Terminal terminal;
  final TerminalController controller;
  final TerminalTheme theme;

  bool _isVisible = false;
  String _searchText = '';
  List<CellOffset> _searchResults = [];
  int _currentResultIndex = -1;
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _regex = false;
  
  // Highlight management
  final List<TerminalHighlight> _searchHighlights = [];
  TerminalHighlight? _currentHighlight;
  
  // Callback for scrolling to matches
  void Function(CellOffset)? onScrollToMatch;
  
  // Debounce timer for search updates
  Timer? _searchUpdateTimer;

  /// Whether the find dialog is currently visible.
  bool get isVisible => _isVisible;

  /// The current search text.
  String get searchText => _searchText;

  /// All search results found in the terminal buffer.
  List<CellOffset> get searchResults => _searchResults;

  /// The index of the currently selected result.
  int get currentResultIndex => _currentResultIndex;

  /// The currently selected result, or null if none.
  CellOffset? get currentResult => 
      _currentResultIndex >= 0 && _currentResultIndex < _searchResults.length
          ? _searchResults[_currentResultIndex]
          : null;

  /// Whether search is case sensitive.
  bool get caseSensitive => _caseSensitive;

  /// Whether to match whole words only.
  bool get wholeWord => _wholeWord;

  /// Whether to use regex matching.
  bool get regex => _regex;

  /// The number of search results.
  int get resultCount => _searchResults.length;

  /// Show the find dialog.
  void show() {
    if (!_isVisible) {
      _isVisible = true;
      notifyListeners();
    }
  }

  /// Hide the find dialog.
  void hide() {
    if (_isVisible) {
      _isVisible = false;
      _searchResults.clear();
      _currentResultIndex = -1;
      _clearHighlights();
      notifyListeners();
    }
  }

  /// Toggle the find dialog visibility.
  void toggle() {
    if (_isVisible) {
      hide();
    } else {
      show();
    }
  }

  /// Set the search text and perform search.
  void setSearchText(String text) {
    _searchText = text;
    _performSearch();
    notifyListeners();
  }

  /// Set case sensitive search.
  void setCaseSensitive(bool value) {
    _caseSensitive = value;
    _performSearch();
    notifyListeners();
  }

  /// Set whole word search.
  void setWholeWord(bool value) {
    _wholeWord = value;
    _performSearch();
    notifyListeners();
  }

  /// Set regex search.
  void setRegex(bool value) {
    _regex = value;
    _performSearch();
    notifyListeners();
  }

  /// Find the next occurrence.
  void findNext() {
    if (_searchResults.isEmpty) return;
    
    _currentResultIndex = (_currentResultIndex + 1) % _searchResults.length;
    _updateCurrentHighlight();
    _scrollToCurrentMatch();
    notifyListeners();
  }

  /// Find the previous occurrence.
  void findPrevious() {
    if (_searchResults.isEmpty) return;
    
    _currentResultIndex = (_currentResultIndex - 1 + _searchResults.length) % _searchResults.length;
    _updateCurrentHighlight();
    _scrollToCurrentMatch();
    notifyListeners();
  }

  /// Perform the actual search in the terminal buffer.
  void _performSearch() {
    _searchResults.clear();
    _currentResultIndex = -1;
    _clearHighlights();

    if (_searchText.isEmpty) {
      notifyListeners();
      return;
    }

    final buffer = terminal.buffer;
    
    // Check if buffer is empty or invalid
    if (buffer.height <= 0 || buffer.viewWidth <= 0) {
      notifyListeners();
      return;
    }
    
    // Check if buffer was cleared (no content at all)
    if (buffer.lines.length == 0) {
      notifyListeners();
      return;
    }
    
    final range = BufferRangeLine(
      CellOffset(0, 0),
      CellOffset(buffer.viewWidth - 1, buffer.height - 1),
    );
    final text = buffer.getText(range);

    if (text.isEmpty) {
      notifyListeners();
      return;
    }

    final searchPattern = _buildSearchPattern();
    final matches = _findMatches(text, searchPattern);

    // Convert text positions to cell offsets and create highlights
    for (final match in matches) {
      final cellOffset = _textPositionToCellOffset(text, match);
      if (cellOffset != null) {
        _searchResults.add(cellOffset);
        
        // Create highlight for this match
        final endOffset = CellOffset(
          cellOffset.x + _searchText.length,
          cellOffset.y,
        );
        final p1 = buffer.createAnchor(cellOffset.x, cellOffset.y);
        final p2 = buffer.createAnchor(endOffset.x, endOffset.y);
        
        final highlight = controller.highlight(
          p1: p1,
          p2: p2,
          color: _getSearchHighlightColor(),
        );
        _searchHighlights.add(highlight);
      }
    }

    if (_searchResults.isNotEmpty) {
      _currentResultIndex = 0;
      _updateCurrentHighlight();
    }

    notifyListeners();
  }

  /// Build the search pattern based on current settings.
  String _buildSearchPattern() {
    String pattern = _searchText;
    
    if (_regex) {
      return pattern;
    }
    
    // Escape special regex characters for literal search
    pattern = RegExp.escape(pattern);
    
    if (_wholeWord) {
      pattern = r'\b' + pattern + r'\b';
    }
    
    return pattern;
  }

  /// Find all matches in the text.
  List<int> _findMatches(String text, String pattern) {
    final matches = <int>[];
    
    try {
      final regex = RegExp(
        pattern,
        caseSensitive: _caseSensitive,
        multiLine: true,
      );
      
      final allMatches = regex.allMatches(text);
      for (final match in allMatches) {
        matches.add(match.start);
      }
    } catch (e) {
      // Invalid regex pattern, return empty results
      if (kDebugMode) {
        print('Invalid regex pattern: $pattern');
      }
    }
    
    return matches;
  }

  /// Convert a text position to a cell offset.
  CellOffset? _textPositionToCellOffset(String text, int position) {
    if (position >= text.length) return null;
    
    int line = 0;
    int column = 0;
    
    for (int i = 0; i < position; i++) {
      if (text[i] == '\n') {
        line++;
        column = 0;
      } else {
        column++;
      }
    }
    
    return CellOffset(column, line);
  }

  /// Clear all search highlights.
  void _clearHighlights() {
    for (final highlight in _searchHighlights) {
      highlight.dispose();
    }
    _searchHighlights.clear();
    _currentHighlight?.dispose();
    _currentHighlight = null;
  }

  /// Update the current highlight to show the selected match.
  void _updateCurrentHighlight() {
    _currentHighlight?.dispose();
    _currentHighlight = null;

    if (_currentResultIndex >= 0 && _currentResultIndex < _searchResults.length) {
      final currentMatch = _searchResults[_currentResultIndex];
      final buffer = terminal.buffer;
      final endOffset = CellOffset(
        currentMatch.x + _searchText.length,
        currentMatch.y,
      );
      final p1 = buffer.createAnchor(currentMatch.x, currentMatch.y);
      final p2 = buffer.createAnchor(endOffset.x, endOffset.y);
      
      _currentHighlight = controller.highlight(
        p1: p1,
        p2: p2,
        color: _getCurrentMatchColor(),
      );
    }
  }

  /// Scroll to the current match.
  void _scrollToCurrentMatch() {
    if (_currentResultIndex >= 0 && 
        _currentResultIndex < _searchResults.length &&
        onScrollToMatch != null) {
      onScrollToMatch!(_searchResults[_currentResultIndex]);
    }
  }

  /// Get the color for search result highlights.
  Color _getSearchHighlightColor() {
    // Use terminal theme's search highlight color with 40% opacity
    return theme.searchHitBackground.withOpacity(0.4);
  }

  /// Get the color for the current match highlight.
  Color _getCurrentMatchColor() {
    // Use terminal theme's current search highlight color with 40% opacity
    return theme.searchHitBackgroundCurrent.withOpacity(0.4);
  }

  /// Handle terminal content changes with debouncing
  void _onTerminalChange() {
    // Only update if find dialog is visible and we have search text
    if (!_isVisible || _searchText.isEmpty) return;
    
    // Cancel previous timer if it exists
    _searchUpdateTimer?.cancel();
    
    // Debounce the search update to avoid excessive updates
    _searchUpdateTimer = Timer(const Duration(milliseconds: 100), () {
      _performSearch();
    });
  }

  /// Reset find state when terminal buffer is cleared
  void _resetFindState() {
    _searchResults.clear();
    _currentResultIndex = -1;
    _clearHighlights();
    notifyListeners();
  }

  /// Manually reset find state (useful when shell changes)
  void resetFindState() {
    _resetFindState();
  }

  @override
  void dispose() {
    // Remove terminal listener
    terminal.removeListener(_onTerminalChange);
    
    // Cancel any pending timer
    _searchUpdateTimer?.cancel();
    
    // Clear highlights
    _clearHighlights();
    
    super.dispose();
  }
}
