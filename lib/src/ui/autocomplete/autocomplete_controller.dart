import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xterm/src/terminal.dart';

class AutocompleteController extends ChangeNotifier {
  final Terminal terminal;
  final String? accessToken;
  final String apiUrl = 'https://vpb5wgy8p7.execute-api.eu-north-1.amazonaws.com/terminal-ai-assistant';

  AutocompleteController({
    required this.terminal,
    this.accessToken,
  }) {
    terminal.addListener(_onTerminalChange);
  }

  List<String> _completions = [];
  int _selectedIndex = 0;
  String? _partialCommand;
  bool _isLoading = false;
  Timer? _debounceTimer;

  List<String> get completions => _completions;
  int get selectedIndex => _selectedIndex;
  String? get partialCommand => _partialCommand;
  bool get isLoading => _isLoading;
  bool get hasCompletions => _completions.isNotEmpty;

  String? get currentCompletion => 
      _completions.isNotEmpty ? _completions[_selectedIndex] : null;

  /// Get the remaining part of the current completion (what would be appended)
  String? get currentCompletionRemainder {
    if (_completions.isEmpty || _selectedIndex >= _completions.length) {
      return null;
    }
    
    final completion = _completions[_selectedIndex];
    final buffer = terminal.buffer;
    final currentLine = buffer.currentLine;
    final cursorX = buffer.cursorX;
    
    // Get the current partial command (text from start of line to cursor)
    final lineText = currentLine.getText(0, cursorX);
    
    // Extract user input by removing prompt
    final userInput = _extractUserInput(lineText);
    final trimmed = userInput.trim();
    
    // Calculate what would be appended
    String? remainder;
    
    // If completion starts with the trimmed command, get the rest
    if (trimmed.isNotEmpty && completion.startsWith(trimmed)) {
      remainder = completion.substring(trimmed.length);
    } else if (trimmed.isNotEmpty) {
      // Try matching from the last word
      final lastSpaceIndex = trimmed.lastIndexOf(' ');
      if (lastSpaceIndex >= 0) {
        final lastWord = trimmed.substring(lastSpaceIndex + 1);
        if (lastWord.isNotEmpty && completion.startsWith(lastWord)) {
          remainder = completion.substring(lastWord.length);
        }
      } else if (completion.startsWith(trimmed)) {
        // No space, but completion starts with trimmed text
        remainder = completion.substring(trimmed.length);
      }
    }
    
    return remainder;
  }

  void _onTerminalChange() {
    // Debounce API calls - only fire after user stops typing
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _updatePartialCommand();
    });
  }

  void _updatePartialCommand() {
    if (accessToken == null) {
      return;
    }

    try {
      final buffer = terminal.buffer;
      final currentLine = buffer.currentLine;
      final cursorX = buffer.cursorX;
      
      // Get text from the current line up to cursor
      final lineText = currentLine.getText(0, cursorX);
      
      // Extract user input by removing prompt
      final userInput = _extractUserInput(lineText);
      final trimmed = userInput.trim();
      
      // Only trigger if there's meaningful text (at least 1 character for faster response)
      if (trimmed.isEmpty) {
        _clearCompletions();
        return;
      }

      // Get the last word (after last space) for better autocomplete
      final lastSpaceIndex = trimmed.lastIndexOf(' ');
      final lastWord = lastSpaceIndex >= 0 
          ? trimmed.substring(lastSpaceIndex + 1) 
          : trimmed;
      
      // Use the full trimmed command for API, but only if it changed
      if (trimmed != _partialCommand) {
        _partialCommand = trimmed;
        // Fetch if there's any text (reduced from 2 to 1 character for faster suggestions)
        if (lastWord.length >= 1) {
          _fetchCompletions(trimmed);
        } else {
          _clearCompletions();
        }
      }
    } catch (e) {
      // Silently handle errors - don't clear completions on error, just skip this update
    }
  }
  
  /// Extract user input from line text by removing prompt patterns
  String _extractUserInput(String lineText) {
    // Try to find prompt patterns (e.g., "user@host % ", "user@host $ ", "C:\> ", etc.)
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

  /// Manually trigger autocomplete check (call this after text input)
  /// Debounces API calls - only fires after user stops typing
  void checkForAutocomplete() {
    _debounceTimer?.cancel();
    // Debounce: wait for user to stop typing (500ms delay for faster response)
    // This ensures API is only called when user pauses, not on every keystroke
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _updatePartialCommand();
    });
  }

  Future<void> _fetchCompletions(String partialCommand) async {
    if (accessToken == null) return;
    
    // Don't make a new API call if one is already in progress for the same command
    if (_isLoading && _partialCommand == partialCommand) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Get context information
      final context = {
        'currentDirectory': '/home/user/project', // TODO: Get actual directory
        'os': 'linux', // TODO: Get actual OS
        'shell': 'bash', // TODO: Get actual shell
      };

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'autoComplete': true,
          'partialCommand': partialCommand,
          'context': context,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['result'] != null) {
          final completions = List<String>.from(data['result']['completions'] ?? []);
          _completions = completions;
          _selectedIndex = 0;
        } else {
          _clearCompletions();
        }
      } else {
        _clearCompletions();
      }
    } catch (e) {
      _clearCompletions();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _clearCompletions() {
    _completions = [];
    _selectedIndex = 0;
    _partialCommand = null;
    notifyListeners();
  }

  void selectNext() {
    if (_completions.isEmpty) return;
    _selectedIndex = (_selectedIndex + 1) % _completions.length;
    notifyListeners();
  }

  void selectPrevious() {
    if (_completions.isEmpty) return;
    _selectedIndex = (_selectedIndex - 1 + _completions.length) % _completions.length;
    notifyListeners();
  }

  void acceptCompletion() {
    if (_completions.isEmpty || _selectedIndex >= _completions.length) return;
    
    // Use the same logic as currentCompletionRemainder to get what to append
    final remainder = currentCompletionRemainder;
    
    // Insert only the remaining part (not the full command)
    if (remainder != null && remainder.isNotEmpty) {
      terminal.textInput(remainder);
    }
    
    // Clear completions after accepting
    _clearCompletions();
  }

  void clear() {
    _clearCompletions();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    terminal.removeListener(_onTerminalChange);
    super.dispose();
  }
}

