# Xterm Example

This is a simple Flutter example demonstrating the xterm terminal emulator package.

## Features

- Terminal emulator with a black background and colored text
- Clear terminal button to erase the display
- Add text button to write content to the terminal
- Basic terminal functionality with cursor and text input

## Running the Example

1. Make sure you have Flutter installed
2. Navigate to this directory
3. Run `flutter pub get` to install dependencies
4. Run `flutter run` to start the app

## How it Works

The example creates a `Terminal` instance and displays it using `TerminalView`. The terminal is configured with a dark theme and includes basic functionality for clearing the display and adding text.

The xterm package is referenced using a path dependency pointing to the parent directory, allowing you to test changes to the xterm package directly.
