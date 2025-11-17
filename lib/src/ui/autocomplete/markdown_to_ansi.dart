/// Converts markdown to ANSI escape codes for terminal display
class MarkdownToAnsi {
  /// Convert markdown text to ANSI-formatted terminal text
  static String convert(String markdown) {
    if (markdown.isEmpty) return '';

    final lines = markdown.split('\n');
    final result = StringBuffer();
    bool lastWasEmpty = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isEmpty = line.trim().isEmpty;
      
      // Collapse multiple consecutive empty lines into single empty line
      if (isEmpty) {
        if (!lastWasEmpty) {
          result.write('\r\n');
          lastWasEmpty = true;
        }
        continue;
      }
      
      lastWasEmpty = false;

      // Headers - subtle formatting
      if (line.startsWith('# ')) {
        result.write(_formatHeader(line.substring(2).trim(), 1));
        result.write('\r\n');
      } else if (line.startsWith('## ')) {
        result.write(_formatHeader(line.substring(3).trim(), 2));
        result.write('\r\n');
      } else if (line.startsWith('### ')) {
        result.write(_formatHeader(line.substring(4).trim(), 3));
        result.write('\r\n');
      } else if (line.startsWith('#### ')) {
        result.write(_formatHeader(line.substring(5).trim(), 4));
        result.write('\r\n');
      }
      // Code blocks
      else if (line.trim().startsWith('```')) {
        final codeBlock = <String>[];
        i++; // Skip opening ```
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeBlock.add(lines[i]);
          i++;
        }
        if (codeBlock.isNotEmpty) {
          result.write(_formatCodeBlock(codeBlock.join('\n')));
          result.write('\r\n');
        }
      }
      // Lists
      else if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
        result.write(_formatListItem(line));
        result.write('\r\n');
      }
      // Blockquotes
      else if (line.trim().startsWith('> ')) {
        result.write(_formatBlockquote(line.substring(2).trim()));
        result.write('\r\n');
      }
      // Regular paragraph
      else {
        result.write(_formatParagraph(line.trim()));
        result.write('\r\n');
      }
    }

    // Remove trailing newline to avoid extra empty line before prompt
    var output = result.toString();
    if (output.endsWith('\r\n')) {
      output = output.substring(0, output.length - 2);
    }
    // Ensure output ends with reset code to prevent formatting from affecting prompt
    if (!output.endsWith('\x1b[0m')) {
      output = '$output\x1b[0m';
    }
    return output;
  }

  static String _formatHeader(String text, int level) {
    // Headers: use faint for transparency (removed bold to keep it transparent)
    final faint = '\x1b[2m';
    final reset = '\x1b[0m';
    return '$faint$text$reset';
  }

  static String _formatParagraph(String text) {
    // Add faint for transparency
    final faint = '\x1b[2m';
    final reset = '\x1b[0m';
    return '$faint${_formatInlineMarkdown(text)}$reset';
  }

  static String _formatCodeBlock(String code) {
    // Code blocks: use a subtle background color to make them stand out like real code blocks
    // Use 256-color mode: \x1b[48;5;236m for dark gray background (236 is a common dark gray)
    final bgColor = '\x1b[48;5;236m'; // Dark gray background (256-color mode)
    final faint = '\x1b[2m';
    final reset = '\x1b[0m';
    final resetBg = '\x1b[49m'; // Reset background color
    final lines = code.split('\n');
    final result = StringBuffer();
    
    for (var i = 0; i < lines.length; i++) {
      // Each line gets: background color + faint text + 2 spaces indent + code + reset
      result.write('$bgColor$faint  ${lines[i]}$reset$resetBg');
      if (i < lines.length - 1) {
        result.write('\r\n');
      }
    }
    
    return result.toString();
  }

  static String _formatListItem(String text) {
    final trimmed = text.trim();
    final content = trimmed.length > 2 ? trimmed.substring(2).trim() : '';
    // Use simple bullet with faint for transparency
    final faint = '\x1b[2m';
    final reset = '\x1b[0m';
    return '$faint  • ${_formatInlineMarkdown(content)}$reset';
  }

  static String _formatBlockquote(String text) {
    // Blockquotes: indent with border, faint for transparency
    final faint = '\x1b[2m';
    final reset = '\x1b[0m';
    return '$faint  │ ${_formatInlineMarkdown(text)}$reset';
  }

  static String _formatInlineMarkdown(String text) {
    final result = StringBuffer();
    var i = 0;
    final faint = '\x1b[2m';
    final reset = '\x1b[0m';

    while (i < text.length) {
      // Bold text **text** - just use faint for transparency (remove bold to keep it transparent)
      if (i < text.length - 1 && text[i] == '*' && text[i + 1] == '*') {
        result.write(faint);
        i += 2;
        final boldEnd = text.indexOf('**', i);
        if (boldEnd != -1) {
          result.write(text.substring(i, boldEnd));
          result.write(reset);
          i = boldEnd + 2;
        } else {
          result.write('**');
        }
      }
      // Italic text *text* - skip, keep as normal text
      else if (text[i] == '*' && (i == 0 || text[i - 1] != '*')) {
        i++;
        final italicEnd = text.indexOf('*', i);
        if (italicEnd != -1 && (italicEnd == i || text[italicEnd - 1] != '*')) {
          // Just remove the asterisks, keep text as-is
          result.write(text.substring(i, italicEnd));
          i = italicEnd + 1;
        } else {
          result.write('*');
        }
      }
      // Inline code `code` - keep as normal text, just remove backticks
      else if (text[i] == '`') {
        i++;
        final codeEnd = text.indexOf('`', i);
        if (codeEnd != -1) {
          result.write(text.substring(i, codeEnd));
          i = codeEnd + 1;
        } else {
          result.write('`');
        }
      }
      // Links [text](url) - just show text, remove brackets and URL
      else if (text[i] == '[') {
        i++;
        final linkTextEnd = text.indexOf(']', i);
        if (linkTextEnd != -1 && 
            linkTextEnd < text.length - 1 && 
            text[linkTextEnd + 1] == '(') {
          final linkText = text.substring(i, linkTextEnd);
          result.write(linkText);
          i = linkTextEnd + 2;
          final urlEnd = text.indexOf(')', i);
          if (urlEnd != -1) {
            i = urlEnd + 1;
          } else {
            result.write('](');
          }
        } else {
          result.write('[');
        }
      }
      else {
        result.write(text[i]);
        i++;
      }
    }

    return result.toString();
  }
}

