import 'dart:typed_data';

/// On web the plugin downloads the bytes itself, so they must be passed in.
bool get pickerWritesBytes => true;

/// Never reached on web (the plugin already downloaded the file).
Future<String> writeBytesToPath(String path, Uint8List bytes) async => path;

/// Never reached on web; kept so the API matches the io implementation.
Future<String> writeBytesToTemp(String fileName, Uint8List bytes) async =>
    fileName;
