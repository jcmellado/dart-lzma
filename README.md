`package:lzma` is a port of LZMA compression algorithm to Dart.

The source code is a manual translation from the original Java version found on
the [LZMA SDK](https://www.7-zip.org/sdk.html).

## How to use it?

If you want to compress data then just call to the `lzma.encode` function, and for the reverse call `lzma.decode`:

````dart
import 'package:lzma/lzma.dart';

final input = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, /*...,*/];
final compressed = lzma.encode(input);
final decompressed = lzma.decode(compressed);
````

## Limitations

* Output data size is limited to 32 bits.
