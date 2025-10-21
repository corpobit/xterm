import 'package:flutter/material.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/terminal_theme.dart';

/// A subtle indicator showing terminal buffer usage in the bottom-right corner
class BufferUsageIndicator extends StatefulWidget {
  final Terminal terminal;
  final TerminalTheme theme;
  final TextStyle textStyle;

  const BufferUsageIndicator({
    super.key,
    required this.terminal,
    required this.theme,
    required this.textStyle,
  });

  @override
  State<BufferUsageIndicator> createState() => _BufferUsageIndicatorState();
}

class _BufferUsageIndicatorState extends State<BufferUsageIndicator> {
  int _currentLines = 0;
  int _maxLines = 0;
  double _usagePercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _updateBufferInfo();
    widget.terminal.addListener(_onTerminalChange);
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalChange);
    super.dispose();
  }

  void _onTerminalChange() {
    if (mounted) {
      _updateBufferInfo();
    }
  }

  void _updateBufferInfo() {
    final buffer = widget.terminal.buffer;
    final newCurrentLines = buffer.height;
    final newMaxLines = buffer.maxLines;
    final newUsagePercentage = newMaxLines > 0 ? (newCurrentLines / newMaxLines) : 0.0;

    if (_currentLines != newCurrentLines || 
        _maxLines != newMaxLines || 
        _usagePercentage != newUsagePercentage) {
      setState(() {
        _currentLines = newCurrentLines;
        _maxLines = newMaxLines;
        _usagePercentage = newUsagePercentage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Usage bar
            Container(
              width: 20,
              height: 8,
              decoration: BoxDecoration(
                color: widget.theme.cursor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _usagePercentage.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: _getUsageColor(),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Text indicator
            Text(
              '$_currentLines/$_maxLines',
              style: widget.textStyle.copyWith(
                color: widget.theme.foreground.withOpacity(0.7),
                fontSize: widget.textStyle.fontSize! * 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getUsageColor() {
    if (_usagePercentage < 0.5) {
      return widget.theme.foreground.withOpacity(0.6); // Green-ish
    } else if (_usagePercentage < 0.8) {
      return Colors.orange.withOpacity(0.7); // Orange
    } else {
      return Colors.red.withOpacity(0.8); // Red
    }
  }
}
