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
    final currentLine = terminal.buffer.absoluteCursorY;
    print('[AgentMode] Terminal changed, current line: $currentLine, last checked: $_lastCheckedLine');
    if (currentLine != _lastCheckedLine) {
      _lastCheckedLine = currentLine;
      print('[AgentMode] Scheduling agent mode check');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('[AgentMode] PostFrameCallback executing');
        checkAndHandleAgentMode();
      });
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
      
      // Extract user input by removing prompt
        final userInput = extractUserInput(lineText);
      final trimmed = userInput.trim();
      
      // Check if this is agent mode (starts with >)
      if (trimmed.startsWith('>')) {
        // Agent mode - don't show autocomplete, just clear it
        _clearCompletions();
        return;
      }
      
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
  
  /// Check if command should trigger agent mode and handle it
  /// Returns true if agent mode was triggered
  /// This should be called after Enter is pressed, so we check the previous line
  bool checkAndHandleAgentMode() {
    if (accessToken == null) {
      print('[AgentMode] No access token');
      return false;
    }
    
    // Prevent multiple simultaneous agent mode checks (but allow even if autocomplete is loading)
    if (_isLoadingAgent) {
      print('[AgentMode] Agent mode already loading');
      return false;
    }
    
    try {
      final buffer = terminal.buffer;
      final absoluteCursorY = buffer.absoluteCursorY;
      
      print('[AgentMode] Checking line $absoluteCursorY');
      
      // After Enter, cursor is on a new line, so check the previous line
      if (absoluteCursorY > 0) {
        final previousLine = buffer.lines[absoluteCursorY - 1];
        final lineText = previousLine.getText(0, previousLine.length);
        
        print('[AgentMode] Previous line text: "$lineText"');
        
        // Fallback: check if line contains > at any position (in case prompt detection failed)
        // Look for pattern like "> something" anywhere in the line
        final directMatch = RegExp(r'>\s*(\S.*)').firstMatch(lineText);
        if (directMatch != null) {
          final message = directMatch.group(1)?.trim() ?? '';
          print('[AgentMode] Direct match found: "$message"');
          if (message.isNotEmpty) {
            _fetchAgentResponse(message);
            return true;
          }
        }
        
        // Extract user input by removing prompt
        final userInput = extractUserInput(lineText);
        final trimmed = userInput.trim();
        print('[AgentMode] Extracted user input: "$trimmed"');
        
        // Check if command starts with > (either directly or after prompt removal)
        if (trimmed.startsWith('>')) {
          final message = trimmed.substring(1).trim();
          print('[AgentMode] Message after >: "$message"');
          if (message.isNotEmpty) {
            _fetchAgentResponse(message);
            return true;
          }
        }
      } else {
        print('[AgentMode] No previous line (absoluteCursorY = $absoluteCursorY)');
      }
    } catch (e) {
      print('[AgentMode] Error: $e');
    }
    
    return false;
  }
  
  Future<void> _fetchAgentResponse(String message) async {
    if (accessToken == null) return;
    
    print('[AgentMode] Fetching agent response for: "$message"');
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

      print('[AgentMode] Response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        String markdown = '';
        
        // Try to parse as JSON first
        try {
          final data = jsonDecode(response.body);
          print('[AgentMode] Response data (JSON): $data');
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
          print('[AgentMode] Response is not JSON, treating as plain text/markdown');
          markdown = response.body;
        }
        
        print('[AgentMode] Markdown response: "$markdown"');
        _agentResponse = markdown;
        
        // Convert markdown to ANSI-formatted text and write to terminal
        if (markdown.isNotEmpty) {
          final ansiText = MarkdownToAnsi.convert(markdown);
          print('[AgentMode] Writing ANSI-formatted markdown to terminal (generative)');
          // Write newline before response
          terminal.write('\r\n');
          // Stream the response character by character for generative effect
          _streamTextToTerminal(ansiText, () {
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
        }
      } else {
        print('[AgentMode] Response status is not 200: ${response.statusCode}');
        print('[AgentMode] Response body: ${response.body}');
        _agentResponse = null;
      }
    } catch (e) {
      print('[AgentMode] Error fetching response: $e');
      _agentResponse = null;
    } finally {
      _isLoadingAgent = false;
      _isLoading = false; // Also clear autocomplete loading flag
      notifyListeners();
    }
  }
  
  /// Extract user input from line text by removing prompt patterns
  /// Made public for use in TerminalView to check for agent mode
  String extractUserInput(String lineText) {
    // Try to find prompt patterns (e.g., "user@host % ", "user@host $ ", "bash-3.2$ ", "C:\> ", etc.)
    int promptEnd = -1;
    
    // Pattern 1: Look for % $ # > followed by space (most common)
    final promptMarkerPattern = RegExp(r'[%$#>]\s+');
    final markerMatches = promptMarkerPattern.allMatches(lineText);
    if (markerMatches.isNotEmpty) {
      promptEnd = markerMatches.last.end;
    }
    
    // Pattern 2: Look for shell prompts like "bash-3.2$ ", "zsh$ ", etc.
    if (promptEnd == -1) {
      final shellPromptPattern = RegExp(r'[\w\-\.]+\$?\s+');
      final shellMatches = shellPromptPattern.allMatches(lineText);
      if (shellMatches.isNotEmpty) {
        // Check if it looks like a shell prompt (starts at beginning of line)
        for (final match in shellMatches) {
          if (match.start == 0) {
            promptEnd = match.end;
            break;
          }
        }
      }
    }
    
    // Pattern 3: Look for user@host pattern followed by space or colon+space
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

