import 'dart:convert';

import 'src/lzma.dart' as lzma_impl;

/// Default instance of the [LzmaCodec]
const LzmaCodec lzma = LzmaCodec();

/// [LzmaCodec] encodes and decodes provided data using the lzma algorithm
class LzmaCodec extends Codec<List<int>, List<int>> {
  const LzmaCodec();

  @override
  Converter<List<int>, List<int>> get encoder => const LzmaEncoder();

  @override
  Converter<List<int>, List<int>> get decoder => const LzmaDecoder();
}

/// Encoder used to convert the given bytes by applying the lzma compression algorithm
class LzmaEncoder extends Converter<List<int>, List<int>> {
  const LzmaEncoder();

  @override
  List<int> convert(List<int> input) {
    final inStream = lzma_impl.InStream(input);
    final outStream = lzma_impl.OutStream();
    lzma_impl.compress(inStream, outStream);
    return outStream.data;
  }
}

/// Encoder used to convert the given bytes by applying the lzma decompression algorithm
/// The decoder will throw if the provided input does not represent an lzma compressed stream
class LzmaDecoder extends Converter<List<int>, List<int>> {
  const LzmaDecoder();

  @override
  List<int> convert(List<int> input) {
    final inStream = lzma_impl.InStream(input);
    final outStream = lzma_impl.OutStream();
    lzma_impl.decompress(inStream, outStream);
    return outStream.data;
  }
}
