import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

Future<Uint8List> loadFaDefaultImageBytes() async {
  final byteData = await rootBundle.load('assets/images/defaultpic.gif');
  return byteData.buffer.asUint8List();
}
