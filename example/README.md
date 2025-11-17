# Xterm Example

This is a simple Flutter example demonstrating the xterm terminal emulator package.

## Features

- Terminal emulator with a black background and colored text
- Clear terminal button to erase the display
- Add text button to write content to the terminal
- Basic terminal functionality with cursor and text input
- AI autocomplete support (optional)

## Running the Example

1. Make sure you have Flutter installed
2. Navigate to this directory
3. Run `flutter pub get` to install dependencies
4. (Optional) Set up AI autocomplete:
   - Create a `.env` file in this directory
   - Add your access token: `ACCESS_TOKEN=your_access_token_here`
   - The `.env` file is gitignored for security
5. Run `flutter run` to start the app

## AI Autocomplete Setup

To enable AI autocomplete in the terminal:

1. Create a `.env` file in the `example` directory
2. Add your access token:
   ```
   ACCESS_TOKEN=your_access_token_here
   ```
3. The autocomplete will automatically be enabled when a valid token is found

## How it Works

The example creates a `Terminal` instance and displays it using `TerminalView`. The terminal is configured with a dark theme and includes basic functionality for clearing the display and adding text.

The xterm package is referenced using a path dependency pointing to the parent directory, allowing you to test changes to the xterm package directly.
