import 'dart:async';
import 'dart:io';

import 'package:lzma/lzma.dart';

Future main(List<String> args) async {
  if (args.length != 2) {
    // ignore: avoid_print
    print('Usage: compress input output');
    return;
  }

  final inFile = File(args[0]);
  final outFile = File(args[1]);

  final encoded = lzma.encode(await inFile.readAsBytes());
  await outFile.writeAsBytes(encoded);
}
