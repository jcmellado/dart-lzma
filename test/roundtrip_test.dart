import 'dart:async';
import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:lzma/lzma.dart';

void main() {
  group('rountrip encoding and decoding', () {
    Future runTest(List<int> input) async {
      final encoded = lzma.encode(input);
      expect(encoded.length, lessThan(input.length * 1.05));
      final decoded = lzma.decode(encoded);
      expect(decoded, input);
    }

    test('same values', () {
      for (var i = 0; i <= 255; i += 17) {
        final input = List.filled(4096, i);
        runTest(input);
      }
    });

    test('random values', () {
      final random = math.Random(9538475);
      for (var i = 0; i < 16; i++) {
        final input = List.generate(4096, (i) => random.nextInt(256));
        runTest(input);
      }
    });
  });
}
