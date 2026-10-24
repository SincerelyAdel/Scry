import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lets the person choose an EPUB file (see MainActivity.kt).
abstract final class BookPicker {
  static const _channel = MethodChannel('scry/files');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// The chosen file's bytes, or null when nothing was chosen.
  static Future<Uint8List?> pick() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('pickBook');
    } on PlatformException catch (e) {
      throw BookPickerException(e.message ?? "Couldn't open the file");
    }
  }
}

class BookPickerException implements Exception {
  BookPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}
