/*
Copyright (c) 2012 Juan Mellado

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

part of lzma;

abstract class _InStream<T> {
  /// Reads a single entity from the stream
  T read();

  /// Reads up to the specified number of elements ([size]) from the stream and places it in the [buffer] starting at [offset]
  int readBlock(List<T> buffer, int offset, int size);

  /// The number of bytes in the stream
  int length();
}

abstract class _OutStream<T> {
  /// Write a single element to the stream
  void write(T value);

  /// Writes [size] elements from [buffer] starting at [offset]
  void writeBlock(List<T> buffer, int offset, int size);

  /// Flushes the stream to it's underlying medium
  void flush();
}

/// Input stream concept, used to read bytes
class InStream implements _InStream<int> {
  final List<int> _data;

  /// Constructor taking the list of bytes to read from
  InStream(this._data);

  int _offset = 0;

  @override
  int read() {
    if (_offset >= length()) {
      return -1;
    }
    return _data[_offset++];
  }

  @override
  int readBlock(List<int> buffer, int offset, int size) {
    if (_offset >= length()) {
      return -1;
    }
    var currentOffset = offset;
    final len = math.min(size, length() - _offset);
    for (var i = 0; i < len; ++i) {
      buffer[currentOffset++] = _data[_offset++];
    }
    return len;
  }

  @override
  int length() => _data.length;
}

/// Output stream concept, used to write bytes
class OutStream implements _OutStream<int> {
  final List<int> data = <int>[];

  @override
  void write(int value) {
    data.add(value);
  }

  @override
  void writeBlock(List<int> buffer, int offset, int size) {
    if (size > 0) {
      data.addAll(buffer.sublist(offset, offset + size));
    }
  }

  @override
  void flush() {}
}
