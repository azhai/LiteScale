import 'dart:io';
import 'dart:typed_data';

/// False on desktop, where `FilePicker.saveFile` only returns a path.
bool get pickerWritesBytes => Platform.isAndroid || Platform.isIOS;

/// Writes [bytes] to the absolute [path] the user picked in the save dialog.
Future<String> writeBytesToPath(String path, Uint8List bytes) async {
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Fallback used when [writeBytesToPath] fails: the process temp directory is
/// always writable, even inside the macOS app sandbox.
Future<String> writeBytesToTemp(String fileName, Uint8List bytes) async {
  final String path = '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '$fileName';
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
