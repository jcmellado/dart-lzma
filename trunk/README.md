**BETA**

**dart-lzma** is a port of LZMA compression algorithm to Dart.

The source code is a manual translation from the original Java version found on the [LZMA SDK](http://www.7-zip.org/sdk.html).

## How to use? 

If you want to compress data then just call to the `compress` function:

```
import "package:lzma/lzma.dart" as LZMA;

var input = new LZMA.InStream(<PUT YOUR DATA BUFFER HERE>);
var output = new LZMA.OutStream();

LZMA.compress(input, output);

//output.data has now your compressed data
```

If you want to decompress data then just call to the `decompress` function:

```
import "package:lzma/lzma.dart" as LZMA;

var input = new LZMA.InStream(<PUT YOUR LZMA DATA BUFFER HERE>);
var output = new LZMA.OutStream();

LZMA.decompress(input, output);

//output.data has now your uncompressed data
```

Where:

* `input` is the input data stream
* `output` is the output data stream

## Streams

Current stream classes will be change in the future.

## Examples

Compress a file and write the result to another one:

```
import "dart:io";
import "package:lzma/lzma.dart" as LZMA;

void main() {
  var options = new Options();

  if (options.arguments.length != 2) {
    print("Usage: compress input output.lzma");
    return;
  }

  var inFile = new File(options.arguments[0]);
  var outFile = new File(options.arguments[1]);

  var input = new LZMA.InStream(inFile.readAsBytesSync());
  var output = new LZMA.OutStream();

  LZMA.compress(input, output);

  outFile.writeAsBytesSync(output.data);
}
```

Decompress a file and write the result to another one:

```
void main() {
  var options = new Options();

  if (options.arguments.length != 2) {
    print("Usage: decompress input.lzma output");
    return;
  }

  var inFile = new File(options.arguments[0]);
  var outFile = new File(options.arguments[1]);

  var input = new LZMA.InStream(inFile.readAsBytesSync());
  var output = new LZMA.OutStream();

  LZMA.decompress(input, output);

  outFile.writeAsBytesSync(output.data);
}
```

## Performance

Be sure to run the library in production mode (not checked mode) with debugging disabled.

## Limitations

  * Output data size is limited to 32 bits.
