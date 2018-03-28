import 'dart:async';
import 'dart:io';

import 'package:lzma/lzma.dart';

Future main(List<String> args) async {
  if (args.length != 2) {
    print('Usage: compress input output');
    return;
  }

  final inFile = new File(args[0]);
  final outFile = new File(args[1]);

  final encoded = lzma.encode(await inFile.readAsBytes());
  await outFile.writeAsBytes(encoded);
}
