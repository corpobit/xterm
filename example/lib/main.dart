import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
    print('[Example] .env file loaded successfully');
  } catch (e) {
    print('[Example] Warning: Could not load .env file: $e');
    print('[Example] AI autocomplete will be disabled');
  }
  runApp(const XtermExampleApp());
}

bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

String get shell {
  if (Platform.isMacOS || Platform.isLinux) {
    return 'bash';
  }

  if (Platform.isWindows) {
    return 'cmd.exe';
  }

  return 'sh';
}

TerminalTargetPlatform get terminalPlatform {
  if (kIsWeb) {
    return TerminalTargetPlatform.web;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return TerminalTargetPlatform.android;
    case TargetPlatform.iOS:
      return TerminalTargetPlatform.ios;
    case TargetPlatform.fuchsia:
      return TerminalTargetPlatform.fuchsia;
    case TargetPlatform.linux:
      return TerminalTargetPlatform.linux;
    case TargetPlatform.macOS:
      return TerminalTargetPlatform.macos;
    case TargetPlatform.windows:
      return TerminalTargetPlatform.windows;
  }
}

class XtermExampleApp extends StatelessWidget {
  const XtermExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xterm Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TerminalPage(),
    );
  }
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final terminal = Terminal(
    maxLines: 10000,
    platform: terminalPlatform,
  );

  final terminalController = TerminalController();

  late final Pty pty;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.endOfFrame.then(
      (_) {
        if (mounted) _startPty();
      },
    );
  }

  void _startPty() {
    try {
      pty = Pty.start(
        shell,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );

      pty.output
          .cast<List<int>>()
          .transform(Utf8Decoder())
          .listen(terminal.write);

      pty.exitCode.then((code) {
        terminal.write('the process exited with exit code $code');
      });

      terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };

      terminal.onResize = (w, h, pw, ph) {
        pty.resize(h, w);
      };
    } catch (e) {
      terminal.write('Error starting PTY: $e');
    }
  }

  @override
  void dispose() {
    try {
      pty.kill();
    } catch (e) {
      // PTY might already be disposed
    }
    terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get access token from .env file
    final accessToken = dotenv.env['ACCESS_TOKEN'];
    final aiAutoCompleteEnabled = accessToken != null && accessToken.isNotEmpty;
    
    print('[Example] AI Autocomplete enabled: $aiAutoCompleteEnabled');
    print('[Example] Access token present: ${accessToken != null && accessToken.isNotEmpty}');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: TerminalView(
          terminal,
          controller: terminalController,
          autofocus: true,
          backgroundOpacity: 0.7,
          showMinimap: true,
          
          aiAutoCompleteEnabled: aiAutoCompleteEnabled,
          aiAccessToken: accessToken,
          onSecondaryTapDown: (details, offset) async {
            final selection = terminalController.selection;
            if (selection != null) {
              final text = terminal.buffer.getText(selection);
              terminalController.clearSelection();
              await Clipboard.setData(ClipboardData(text: text));
            } else {
              final data = await Clipboard.getData('text/plain');
              final text = data?.text;
              if (text != null) {
                terminal.paste(text);
              }
            }
          },
        ),
      ),
    );
  }
}
