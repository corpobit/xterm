import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/autocomplete/markdown_to_ansi.dart';

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
  bool _isLoadingAgent = false; // Separate flag for agent mode loading
  Timer? _debounceTimer;
  String? _agentResponse; // Markdown response from agent mode
  int? _lastCheckedLine; // Track last line we checked to avoid duplicate checks
  bool _isStreaming = false; // Track if AI response is currently streaming
  Timer? _streamTimer; // Timer for streaming chunks

  List<String> get completions => _completions;
  int get selectedIndex => _selectedIndex;
  String? get partialCommand => _partialCommand;
  bool get isLoading => _isLoading;
  bool get isLoadingAgent => _isLoadingAgent;
  bool get hasCompletions => _completions.isNotEmpty;
  String? get agentResponse => _agentResponse;
  bool get isStreaming => _isStreaming; // Expose streaming state
  
  /// Check if there's actual user input (not empty, excluding prompt)
  bool get hasValidInput {
    try {
      final buffer = terminal.buffer;
      final currentLine = buffer.currentLine;
      final cursorX = buffer.cursorX;
      final lineText = currentLine.getText(0, cursorX);
      
      // Extract user input by removing prompt
      final userInput = extractUserInput(lineText);
      final trimmed = userInput.trim();
      
      // Must have at least 1 non-whitespace character
      if (trimmed.isEmpty) {
        return false;
      }
      
      // Get the last word to ensure there's actual content
      final lastSpaceIndex = trimmed.lastIndexOf(' ');
      final lastWord = lastSpaceIndex >= 0 
          ? trimmed.substring(lastSpaceIndex + 1).trim() 
          : trimmed.trim();
      
      // Only return true if there's actual content (not just spaces)
      return lastWord.isNotEmpty && lastWord.length > 0;
    } catch (e) {
      return false;
    }
  }

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
        final userInput = extractUserInput(lineText);
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
    // Check for agent mode when terminal changes (e.g., after Enter is pressed)
    // This is more reliable than using a delay
    final absoluteCursorY = terminal.buffer.absoluteCursorY;
    if (absoluteCursorY != _lastCheckedLine) {
      _lastCheckedLine = absoluteCursorY;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        checkAndHandleAgentMode();
      });
    }
    
    try {
      final buffer = terminal.buffer;
      final currentLine = buffer.currentLine;
      final cursorX = buffer.cursorX;
      final lineText = currentLine.getText(0, cursorX);
      final userInput = extractUserInput(lineText);
      final trimmed = userInput.trim();
      
      if (trimmed.isEmpty) {
        _clearCompletions();
        _debounceTimer?.cancel();
        return;
      }
    } catch (e) {
      _clearCompletions();
      _debounceTimer?.cancel();
      return;
    }
    
    // Check if current line contains ">" (agent mode) - disable autocomplete
    // Check the original lineText before prompt extraction to catch ">" anywhere
    try {
      final buffer = terminal.buffer;
      final currentLine = buffer.currentLine;
      final cursorX = buffer.cursorX;
      final lineText = currentLine.getText(0, cursorX);
      
      // Check if line contains ">" pattern (agent mode command)
      // Look for pattern like "> something" anywhere in the line
      if (lineText.contains('>')) {
        final agentMatch = RegExp(r'>\s*(\S.*)').firstMatch(lineText);
        if (agentMatch != null) {
          // Agent mode - clear any existing completions and don't trigger autocomplete
          _clearCompletions();
          _debounceTimer?.cancel();
          return;
        }
      }
    } catch (e) {
      // If check fails, continue with normal autocomplete flow
    }
    
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
      
      // Check if line contains ">" pattern (agent mode command) BEFORE prompt extraction
      // Look for pattern like "> something" anywhere in the line
      if (lineText.contains('>')) {
        final agentMatch = RegExp(r'>\s*(\S.*)').firstMatch(lineText);
        if (agentMatch != null) {
          // Agent mode - don't show autocomplete, just clear it
          _clearCompletions();
          return;
        }
      }
      
      final userInput = extractUserInput(lineText);
      final trimmed = userInput.trim();
      
      if (trimmed.isEmpty) {
        _clearCompletions();
        return;
      }

      final lastSpaceIndex = trimmed.lastIndexOf(' ');
      final lastWord = lastSpaceIndex >= 0 
          ? trimmed.substring(lastSpaceIndex + 1).trim() 
          : trimmed.trim();
      
      if (lastWord.isEmpty) {
        _clearCompletions();
        return;
      }
      
      if (trimmed != _partialCommand) {
        _partialCommand = trimmed;
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
  
  /// Check if command should trigger agent mode and handle it
  /// Returns true if agent mode was triggered
  /// This should be called after Enter is pressed, so we check the previous line
  bool checkAndHandleAgentMode() {
    if (accessToken == null) {
      return false;
    }
    
    // Prevent multiple simultaneous agent mode checks (but allow even if autocomplete is loading)
    if (_isLoadingAgent) {
      return false;
    }
    
    try {
      final buffer = terminal.buffer;
      final absoluteCursorY = buffer.absoluteCursorY;
      
      // After Enter, cursor is on a new line, so check the previous line
      if (absoluteCursorY > 0) {
        final previousLine = buffer.lines[absoluteCursorY - 1];
        final lineText = previousLine.getText(0, previousLine.length);
        
        // Extract user input by removing prompt
        final userInput = extractUserInput(lineText);
        final trimmed = userInput.trim();
        
        // Check if user input starts with ">" (agent mode command)
        // Since extractUserInput removes the prompt, any > here is user input
        if (trimmed.startsWith('>')) {
          // Extract message after ">" (e.g., "> hi" -> "hi", ">" -> "")
          final message = trimmed.length > 1 ? trimmed.substring(1).trim() : '';
          _fetchAgentResponse(message);
          return true;
        }
      }
    } catch (e) {
      // Silently handle errors
    }
    
    return false;
  }
  
  Future<void> _fetchAgentResponse(String message) async {
    if (accessToken == null) return;
    
    _isLoadingAgent = true;
    _agentResponse = null;
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
          'agentMode': true,
          'message': message,
          'context': context,
        }),
      );

      if (response.statusCode == 200) {
        String markdown = '';
        
        // Try to parse as JSON first
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['success'] == true && data['result'] != null) {
            // Get markdown from JSON response
            markdown = data['result']['markdown'] ?? data['result']['response'] ?? '';
          } else if (data is Map && data['markdown'] != null) {
            markdown = data['markdown'] ?? '';
          } else if (data is Map && data['response'] != null) {
            markdown = data['response'] ?? '';
          }
        } catch (e) {
          // If JSON parsing fails, treat the response body as plain markdown
          markdown = response.body;
        }
        
        _agentResponse = markdown;
        
        // Convert markdown to ANSI-formatted text and write to terminal
        if (markdown.isNotEmpty) {
          final ansiText = MarkdownToAnsi.convert(markdown);
          // Write newline before response
          terminal.write('\r\n');
          // Stream the response character by character for generative effect
          _streamTextToTerminal(ansiText, () {
            // Clear agent loading flag immediately when streaming completes
            // This unblocks input as soon as streaming finishes
            _isLoadingAgent = false;
            _isLoading = false; // Also clear autocomplete loading flag
            notifyListeners();
            
            // After streaming is complete, reset all formatting and add newline
            // Write reset codes AFTER newline to ensure they apply to the next line
            // Use comprehensive reset codes to ensure everything is reset:
            // \x1b[0m = reset all attributes (bold, faint, etc.)
            // \x1b[22m = explicitly unset bold/faint
            // \x1b[39m = reset foreground color to default
            // \x1b[49m = reset background color to default
            terminal.write('\r\n\x1b[0m\x1b[22m\x1b[39m\x1b[49m');
            // Send Enter key to trigger shell to show a new prompt
            Future.delayed(const Duration(milliseconds: 150), () {
              terminal.keyInput(TerminalKey.enter);
            });
          });
        } else {
          // No markdown to stream, clear loading flag immediately
          _isLoadingAgent = false;
          _isLoading = false;
          notifyListeners();
        }
      } else {
        _agentResponse = null;
        _isLoadingAgent = false;
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      _agentResponse = null;
      _isLoadingAgent = false;
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Extract user input from line text by removing prompt patterns
  /// Made public for use in TerminalView to check for agent mode
  /// Returns only the user input, never the prompt
  String extractUserInput(String lineText) {
    if (lineText.isEmpty) {
      return '';
    }
    
    int promptEnd = -1;
    
    final promptMarkerPattern = RegExp(r'[%$#>]\s+');
    
    final pathEndingWithGreater = RegExp(r'^[~/][\w\.\-/]+\>\s*');
    final pathMatch = pathEndingWithGreater.firstMatch(lineText);
    if (pathMatch != null) {
      promptEnd = pathMatch.end;
    }
    
    if (promptEnd == -1) {
      final shellPromptPattern = RegExp(r'^[\w\-\.]+\$?\s+');
      final shellMatch = shellPromptPattern.firstMatch(lineText);
      if (shellMatch != null) {
        promptEnd = shellMatch.end;
      }
    }
    
    if (promptEnd == -1) {
      final markerMatch = promptMarkerPattern.firstMatch(lineText);
      if (markerMatch != null) {
        promptEnd = markerMatch.end;
      }
    }
    
    if (promptEnd == -1) {
      final userHostPattern = RegExp(r'^\w+@[\w\-\.]+[:\s]+');
      final userHostMatch = userHostPattern.firstMatch(lineText);
      if (userHostMatch != null) {
        final end = userHostMatch.end;
        if (end < lineText.length) {
          final afterMatch = lineText.substring(end);
          final markerMatch = promptMarkerPattern.firstMatch(afterMatch);
          if (markerMatch != null) {
            promptEnd = end + markerMatch.end;
          } else {
            promptEnd = end;
          }
        } else {
          promptEnd = end;
        }
      }
    }
    
    // Pattern 4: Look for Windows-style prompts like "C:\> ", "C:\Users\> ", etc.
    if (promptEnd == -1) {
      final windowsPromptPattern = RegExp(r'^[A-Z]:\\[^>]*>\s+');
      final windowsMatch = windowsPromptPattern.firstMatch(lineText);
      if (windowsMatch != null) {
        promptEnd = windowsMatch.end;
      }
    }
    
    // Extract user input after prompt
    if (promptEnd > 0 && promptEnd <= lineText.length) {
      final userInput = lineText.substring(promptEnd);
      return userInput;
    }
    
    // If no prompt pattern found, return the whole line
    // But this should rarely happen if prompt extraction is working
    return lineText;
  }

  /// Manually trigger autocomplete check (call this after text input)
  /// Debounces API calls - only fires after user stops typing
  void checkForAutocomplete() {
    // Check if current line contains ">" (agent mode) - disable autocomplete
    // Check the original lineText before prompt extraction to catch ">" anywhere
    try {
      final buffer = terminal.buffer;
      final currentLine = buffer.currentLine;
      final cursorX = buffer.cursorX;
      final lineText = currentLine.getText(0, cursorX);
      
      // Check if line contains ">" pattern (agent mode command)
      // Look for pattern like "> something" anywhere in the line
      if (lineText.contains('>')) {
        final agentMatch = RegExp(r'>\s*(\S.*)').firstMatch(lineText);
        if (agentMatch != null) {
          // Agent mode - clear any existing completions and don't trigger autocomplete
          _clearCompletions();
          _debounceTimer?.cancel();
          return;
        }
      }
    } catch (e) {
      // If check fails, continue with normal autocomplete flow
    }
    
    _debounceTimer?.cancel();
    // Debounce: wait for user to stop typing (500ms delay for faster response)
    // This ensures API is only called when user pauses, not on every keystroke
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _updatePartialCommand();
    });
  }

  Future<void> _fetchCompletions(String partialCommand) async {
    if (accessToken == null) return;
    
    final trimmed = partialCommand.trim();
    if (trimmed.isEmpty) {
      _clearCompletions();
      return;
    }
    
    String commandToSend = extractUserInput(trimmed).trim();
    
    if (commandToSend.isEmpty) {
      _clearCompletions();
      return;
    }
    
    if (commandToSend.startsWith(RegExp(r'[%$#>]\s+')) ||
        RegExp(r'^[\w\-\.]+\$?\s+').hasMatch(commandToSend) ||
        RegExp(r'^\w+@[\w\-\.]+[:\s]+').hasMatch(commandToSend)) {
      _clearCompletions();
      return;
    }
    
    // Don't make a new API call if one is already in progress for the same command
    if (_isLoading && _partialCommand == commandToSend) {
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
          'partialCommand': commandToSend,
          'context': context,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['result'] != null) {
          final completions = List<String>.from(data['result']['completions'] ?? []);
          
          // CRITICAL: Validate input is still valid before setting completions
          // User might have cleared input while API call was in progress
          if (!hasValidInput) {
            _clearCompletions();
            return;
          }
          
          _completions = completions;
          _selectedIndex = 0;
          
          // Double-check: if remainder is invalid, clear immediately
          final remainder = currentCompletionRemainder;
          if (remainder == null || remainder.isEmpty) {
            _clearCompletions();
            return;
          }
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

  bool checkAndDismissIfInvalid() {
    if (!hasCompletions) {
      return false;
    }
    
    if (!hasValidInput) {
      _clearCompletions();
      return true;
    }
    
    try {
      final remainder = currentCompletionRemainder;
      if (remainder == null || remainder.isEmpty) {
        _clearCompletions();
        return true;
      }
    } catch (e) {
      _clearCompletions();
      return true;
    }
    
    return false;
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
    notifyListeners();
  }

  /// Stream text to terminal character by character for generative effect
  void _streamTextToTerminal(String text, VoidCallback onComplete) {
    if (text.isEmpty) {
      onComplete();
      return;
    }

    _isStreaming = true;
    notifyListeners();

    var index = 0;
    const chunkSize = 3; // Write 3 characters at a time for smoother effect
    const delayMs = 20; // Delay between chunks (milliseconds)

    void writeNextChunk() {
      // Check if streaming was cancelled
      if (!_isStreaming) {
        onComplete();
        return;
      }

      if (index >= text.length) {
        _isStreaming = false;
        notifyListeners();
        onComplete();
        return;
      }

      final endIndex = (index + chunkSize).clamp(0, text.length);
      final chunk = text.substring(index, endIndex);
      terminal.write(chunk);
      index = endIndex;

      if (index < text.length) {
        _streamTimer = Timer(Duration(milliseconds: delayMs), writeNextChunk);
      } else {
        _isStreaming = false;
        notifyListeners();
        onComplete();
      }
    }

    // Start streaming
    writeNextChunk();
  }

  /// Stop streaming AI response (called by Control+C)
  void stopStreaming() {
    if (_isStreaming) {
      _isStreaming = false;
      _isLoadingAgent = false; // Also clear agent loading flag
      _isLoading = false;
      _streamTimer?.cancel();
      _streamTimer = null;
      notifyListeners();
      // Reset all formatting and write a newline to clean up
      // Use comprehensive reset codes to ensure everything is reset
      terminal.write('\x1b[0m\x1b[22m\x1b[39m\x1b[49m\r\n');
      // Trigger shell prompt
      Future.delayed(const Duration(milliseconds: 150), () {
        terminal.keyInput(TerminalKey.enter);
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _streamTimer?.cancel();
    terminal.removeListener(_onTerminalChange);
    super.dispose();
  }
}

