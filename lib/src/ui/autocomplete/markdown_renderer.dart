import 'package:flutter/material.dart';
import 'package:xterm/src/ui/terminal_theme.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';

/// Custom markdown renderer for terminal agent responses
class MarkdownRenderer {
  final TerminalTheme theme;
  final TerminalStyle textStyle;

  MarkdownRenderer({
    required this.theme,
    required this.textStyle,
  });

  /// Parse markdown text and return a widget tree
  Widget build(String markdown) {
    if (markdown.isEmpty) {
      return const SizedBox.shrink();
    }

    final lines = markdown.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.trim().isEmpty) {
        widgets.add(SizedBox(height: textStyle.fontSize * textStyle.height));
        continue;
      }

      // Headers
      if (line.startsWith('# ')) {
        widgets.add(_buildHeader(line.substring(2), 1));
      } else if (line.startsWith('## ')) {
        widgets.add(_buildHeader(line.substring(3), 2));
      } else if (line.startsWith('### ')) {
        widgets.add(_buildHeader(line.substring(4), 3));
      } else if (line.startsWith('#### ')) {
        widgets.add(_buildHeader(line.substring(5), 4));
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
          widgets.add(_buildCodeBlock(codeBlock.join('\n')));
        }
      }
      // Lists
      else if (line.trim().startsWith('- ') || line.trim().startsWith('* ')) {
        widgets.add(_buildListItem(line));
      }
      // Blockquotes
      else if (line.trim().startsWith('> ')) {
        widgets.add(_buildBlockquote(line.substring(2)));
      }
      // Regular paragraph
      else {
        widgets.add(_buildParagraph(line));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildHeader(String text, int level) {
    final fontSize = textStyle.fontSize * (1.8 - (level * 0.2));
    final fontWeight = FontWeight.bold;
    
    return Padding(
      padding: EdgeInsets.only(
        top: level == 1 ? textStyle.fontSize * 0.5 : textStyle.fontSize * 0.3,
        bottom: textStyle.fontSize * 0.3,
      ),
      child: Text(
        text,
        style: textStyle.toTextStyle(
          color: theme.foreground,
          bold: true,
        ).copyWith(
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: textStyle.fontSize * 0.3),
      child: _buildRichText(text),
    );
  }

  Widget _buildCodeBlock(String code) {
    return Container(
      margin: EdgeInsets.only(
        top: textStyle.fontSize * 0.3,
        bottom: textStyle.fontSize * 0.3,
      ),
      padding: EdgeInsets.all(textStyle.fontSize * 0.5),
      decoration: BoxDecoration(
        color: theme.foreground.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        code,
        style: textStyle.toTextStyle(
          color: theme.foreground,
        ).copyWith(
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildListItem(String text) {
    final content = text.trim().substring(2); // Remove "- " or "* "
    return Padding(
      padding: EdgeInsets.only(
        left: textStyle.fontSize,
        bottom: textStyle.fontSize * 0.2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: textStyle.toTextStyle(color: theme.foreground),
          ),
          Expanded(
            child: _buildRichText(content),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockquote(String text) {
    return Container(
      margin: EdgeInsets.only(
        left: textStyle.fontSize,
        top: textStyle.fontSize * 0.2,
        bottom: textStyle.fontSize * 0.2,
      ),
      padding: EdgeInsets.only(left: textStyle.fontSize * 0.5),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.foreground.withOpacity(0.5),
            width: 2,
          ),
        ),
      ),
      child: _buildRichText(text),
    );
  }

  Widget _buildRichText(String text) {
    final spans = <TextSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    while (i < text.length) {
      // Bold text **text**
      if (i < text.length - 1 && text[i] == '*' && text[i + 1] == '*') {
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(
            text: buffer.toString(),
            style: textStyle.toTextStyle(color: theme.foreground),
          ));
          buffer.clear();
        }
        i += 2;
        final boldEnd = text.indexOf('**', i);
        if (boldEnd != -1) {
          spans.add(TextSpan(
            text: text.substring(i, boldEnd),
            style: textStyle.toTextStyle(
              color: theme.foreground,
              bold: true,
            ),
          ));
          i = boldEnd + 2;
        } else {
          buffer.write('**');
        }
      }
      // Italic text *text*
      else if (text[i] == '*' && (i == 0 || text[i - 1] != '*')) {
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(
            text: buffer.toString(),
            style: textStyle.toTextStyle(color: theme.foreground),
          ));
          buffer.clear();
        }
        i++;
        final italicEnd = text.indexOf('*', i);
        if (italicEnd != -1 && (italicEnd == i || text[italicEnd - 1] != '*')) {
          spans.add(TextSpan(
            text: text.substring(i, italicEnd),
            style: textStyle.toTextStyle(
              color: theme.foreground,
              italic: true,
            ),
          ));
          i = italicEnd + 1;
        } else {
          buffer.write('*');
        }
      }
      // Inline code `code`
      else if (text[i] == '`') {
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(
            text: buffer.toString(),
            style: textStyle.toTextStyle(color: theme.foreground),
          ));
          buffer.clear();
        }
        i++;
        final codeEnd = text.indexOf('`', i);
        if (codeEnd != -1) {
          spans.add(TextSpan(
            text: text.substring(i, codeEnd),
            style: textStyle.toTextStyle(
              color: theme.foreground,
            ).copyWith(
              fontFamily: 'monospace',
              backgroundColor: theme.foreground.withOpacity(0.15),
            ),
          ));
          i = codeEnd + 1;
        } else {
          buffer.write('`');
        }
      }
      // Links [text](url)
      else if (text[i] == '[') {
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(
            text: buffer.toString(),
            style: textStyle.toTextStyle(color: theme.foreground),
          ));
          buffer.clear();
        }
        i++;
        final linkTextEnd = text.indexOf(']', i);
        if (linkTextEnd != -1 && 
            linkTextEnd < text.length - 1 && 
            text[linkTextEnd + 1] == '(') {
          final linkText = text.substring(i, linkTextEnd);
          i = linkTextEnd + 2;
          final urlEnd = text.indexOf(')', i);
          if (urlEnd != -1) {
            spans.add(TextSpan(
              text: linkText,
              style: textStyle.toTextStyle(
                color: theme.cursor,
                underline: true,
              ),
            ));
            i = urlEnd + 1;
          } else {
            buffer.write('[');
            buffer.write(linkText);
            buffer.write('](');
          }
        } else {
          buffer.write('[');
        }
      }
      else {
        buffer.write(text[i]);
        i++;
      }
    }

    if (buffer.isNotEmpty) {
      spans.add(TextSpan(
        text: buffer.toString(),
        style: textStyle.toTextStyle(color: theme.foreground),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: textStyle.toTextStyle(color: theme.foreground),
    );
  }
}

