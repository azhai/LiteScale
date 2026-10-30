/// Writing files chosen through the platform save dialog.
///
/// `file_picker` behaves differently per platform: on Android/iOS `saveFile`
/// expects the raw bytes and writes them itself, while on desktop (macOS,
/// Windows, Linux) it rejects `bytes` outright and only hands back a path —
/// the caller must write the file. Web has no file system at all, the plugin
/// turns the call into a download.
///
/// This conditional export hides that split: [pickerWritesBytes] tells the
/// caller whether it still has to write, [writeBytesToPath] does the writing,
/// and [writeBytesToTemp] is the fallback when the chosen location is not
/// writable (sandbox denial, read-only volume, ...).
library;

export 'file_saver_stub.dart' if (dart.library.io) 'file_saver_io.dart';
