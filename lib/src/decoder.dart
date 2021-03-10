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

/*
References:
- "LZMA SDK" by Igor Pavlov
  http://www.7-zip.org/sdk.html
*/

part of lzma;

bool decompress(InStream inStream, OutStream outStream) {
  const propertiesSize = 5;

  final properties = List.filled(propertiesSize, 0);
  if (inStream.readBlock(properties, 0, propertiesSize) != propertiesSize) {
    throw Exception('Input .lzma file is too short');
  }

  final decoder = Decoder();
  if (!decoder.setDecoderProperties(properties)) {
    throw Exception('Incorrect stream properties');
  }

  var outSize = 0;
  for (var i = 0; i < 8; ++i) {
    final value = inStream.read();
    if (value < 0) {
      throw Exception("Can't read stream size");
    }
    // ignore: avoid_as
    outSize += value * (math.pow(2, 8 * i) as int);
  }

  if (!decoder.decode(inStream, outStream, outSize)) {
    throw Exception('Error in data stream');
  }

  return true;
}

class LenDecoder {
  final List<int> _choice = List.filled(2, 0);
  final List<BitTreeDecoder?> _lowCoder =
      List.filled(Base.kNumPosStatesMax, null);
  final List<BitTreeDecoder?> _midCoder =
      List.filled(Base.kNumPosStatesMax, null);
  final BitTreeDecoder _highCoder = BitTreeDecoder(Base.kNumHighLenBits);
  int _numPosStates = 0;

  void create(int numPosStates) {
    for (; _numPosStates < numPosStates; ++_numPosStates) {
      _lowCoder[_numPosStates] = BitTreeDecoder(Base.kNumLowLenBits);
      _midCoder[_numPosStates] = BitTreeDecoder(Base.kNumMidLenBits);
    }
  }

  void init() {
    RangeDecoder.initBitModels(_choice);

    for (var i = 0; i < _numPosStates; ++i) {
      _lowCoder[i]!.init();
      _midCoder[i]!.init();
    }

    _highCoder.init();
  }

  int decode(RangeDecoder rangeDecoder, int posState) {
    if (rangeDecoder.decodeBit(_choice, 0) == 0) {
      return _lowCoder[posState]!.decode(rangeDecoder);
    }

    if (rangeDecoder.decodeBit(_choice, 1) == 0) {
      return Base.kNumLowLenSymbols + _midCoder[posState]!.decode(rangeDecoder);
    }

    return Base.kNumLowLenSymbols +
        Base.kNumMidLenSymbols +
        _highCoder.decode(rangeDecoder);
  }
}

class Decoder2 {
  final List<int> _decoders = List<int>.filled(0x300, 0);

  void init() {
    RangeDecoder.initBitModels(_decoders);
  }

  int decodeNormal(RangeDecoder rangeDecoder) {
    var symbol = 1;

    do {
      symbol = (symbol << 1) | rangeDecoder.decodeBit(_decoders, symbol);
    } while (symbol < 0x100);

    return symbol & 0xff;
  }

  int decodeWithMatchByte(RangeDecoder rangeDecoder, int matchByte) {
    var symbol = 1;

    var currentMatchByte = matchByte;
    do {
      final matchBit = (currentMatchByte >> 7) & 1;
      currentMatchByte <<= 1;

      final bit =
          rangeDecoder.decodeBit(_decoders, ((1 + matchBit) << 8) + symbol);
      symbol = (symbol << 1) | bit;

      if (matchBit != bit) {
        while (symbol < 0x100) {
          symbol = (symbol << 1) | rangeDecoder.decodeBit(_decoders, symbol);
        }
        break;
      }
    } while (symbol < 0x100);

    return symbol & 0xff;
  }
}

class LiteralDecoder {
  List<Decoder2>? _coders;
  int _numPrevBits = 0;
  int _numPosBits = 0;
  int _posMask = 0;

  void create(int numPosBits, int numPrevBits) {
    if ((_coders != null) &&
        (_numPrevBits == numPrevBits) &&
        (_numPosBits == numPosBits)) {
      return;
    }
    _numPosBits = numPosBits;
    _posMask = (1 << numPosBits) - 1;
    _numPrevBits = numPrevBits;

    final numStates = 1 << (_numPrevBits + _numPosBits);
    _coders = List<Decoder2>.generate(numStates, (_) => Decoder2());
  }

  void init() {
    final numStates = 1 << (_numPrevBits + _numPosBits);
    for (var i = 0; i < numStates; ++i) {
      _coders![i].init();
    }
  }

  Decoder2 getDecoder(int pos, int prevByte) =>
      _coders![((pos & _posMask) << _numPrevBits) +
          ((prevByte & 0xff) >> (8 - _numPrevBits))];
}

class Decoder {
  final OutWindow _outWindow = OutWindow();
  final RangeDecoder _rangeDecoder = RangeDecoder();

  final List<int> _isMatchDecoders =
      List<int>.filled(Base.kNumStates << Base.kNumPosStatesBitsMax, 0);
  final List<int> _isRepDecoders = List<int>.filled(Base.kNumStates, 0);
  final List<int> _isRepG0Decoders = List<int>.filled(Base.kNumStates, 0);
  final List<int> _isRepG1Decoders = List<int>.filled(Base.kNumStates, 0);
  final List<int> _isRepG2Decoders = List<int>.filled(Base.kNumStates, 0);
  final List<int> _isRep0LongDecoders =
      List<int>.filled(Base.kNumStates << Base.kNumPosStatesBitsMax, 0);

  final List<BitTreeDecoder> _posSlotDecoder = List<BitTreeDecoder>.generate(
      Base.kNumLenToPosStates, (_) => BitTreeDecoder(Base.kNumPosSlotBits));
  final List<int> _posDecoders =
      List<int>.filled(Base.kNumFullDistances - Base.kEndPosModelIndex, 0);

  final BitTreeDecoder _posAlignDecoder = BitTreeDecoder(Base.kNumAlignBits);

  final LenDecoder _lenDecoder = LenDecoder();
  final LenDecoder _repLenDecoder = LenDecoder();

  final LiteralDecoder _literalDecoder = LiteralDecoder();

  int _dictionarySize = -1;
  int _dictionarySizeCheck = -1;

  int _posStateMask = 0;

  Decoder();

  bool _setDictionarySize(int dictionarySize) {
    if (dictionarySize < 0) {
      return false;
    }

    if (_dictionarySize != dictionarySize) {
      _dictionarySize = dictionarySize;
      _dictionarySizeCheck = math.max(_dictionarySize, 1);
      _outWindow.create(math.max(_dictionarySizeCheck, 4096));
    }

    return true;
  }

  bool _setLcLpPb(int lc, int lp, int pb) {
    if ((lc > Base.kNumLitContextBitsMax) ||
        (lp > 4) ||
        (pb > Base.kNumPosStatesBitsMax)) {
      return false;
    }

    _literalDecoder.create(lp, lc);

    final numPosStates = 1 << pb;
    _lenDecoder.create(numPosStates);
    _repLenDecoder.create(numPosStates);
    _posStateMask = numPosStates - 1;

    return true;
  }

  void init() {
    _outWindow.init(false);

    RangeDecoder.initBitModels(_isMatchDecoders);
    RangeDecoder.initBitModels(_isRep0LongDecoders);
    RangeDecoder.initBitModels(_isRepDecoders);
    RangeDecoder.initBitModels(_isRepG0Decoders);
    RangeDecoder.initBitModels(_isRepG1Decoders);
    RangeDecoder.initBitModels(_isRepG2Decoders);
    RangeDecoder.initBitModels(_posDecoders);

    _literalDecoder.init();

    for (var i = 0; i < Base.kNumLenToPosStates; ++i) {
      _posSlotDecoder[i].init();
    }

    _lenDecoder.init();
    _repLenDecoder.init();
    _posAlignDecoder.init();
    _rangeDecoder.init();
  }

  bool decode(InStream inStream, OutStream outStream, int outSize) {
    _rangeDecoder.setStream(inStream);
    _outWindow.setStream(outStream);

    init();

    var state = Base.stateInit;
    var rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;

    var nowPos64 = 0;
    var prevByte = 0;

    while ((outSize < 0) || (nowPos64 < outSize)) {
      final posState = nowPos64 & _posStateMask;

      if (_rangeDecoder.decodeBit(_isMatchDecoders,
              (state << Base.kNumPosStatesBitsMax) + posState) ==
          0) {
        final decoder2 = _literalDecoder.getDecoder(nowPos64, prevByte);

        if (!Base.stateIsCharState(state)) {
          prevByte = decoder2.decodeWithMatchByte(
              _rangeDecoder, _outWindow.getByte(rep0));
        } else {
          prevByte = decoder2.decodeNormal(_rangeDecoder);
        }
        _outWindow.putByte(prevByte);

        state = Base.stateUpdateChar(state);

        ++nowPos64;
      } else {
        int len;
        if (_rangeDecoder.decodeBit(_isRepDecoders, state) == 1) {
          len = 0;
          if (_rangeDecoder.decodeBit(_isRepG0Decoders, state) == 0) {
            if (_rangeDecoder.decodeBit(_isRep0LongDecoders,
                    (state << Base.kNumPosStatesBitsMax) + posState) ==
                0) {
              state = Base.stateUpdateShortRep(state);
              len = 1;
            }
          } else {
            int distance;
            if (_rangeDecoder.decodeBit(_isRepG1Decoders, state) == 0) {
              distance = rep1;
            } else {
              if (_rangeDecoder.decodeBit(_isRepG2Decoders, state) == 0) {
                distance = rep2;
              } else {
                distance = rep3;
                rep3 = rep2;
              }
              rep2 = rep1;
            }
            rep1 = rep0;
            rep0 = distance;
          }
          if (len == 0) {
            len = _repLenDecoder.decode(_rangeDecoder, posState) +
                Base.kMatchMinLen;
            state = Base.stateUpdateRep(state);
          }
        } else {
          rep3 = rep2;
          rep2 = rep1;
          rep1 = rep0;

          len = Base.kMatchMinLen + _lenDecoder.decode(_rangeDecoder, posState);
          state = Base.stateUpdateMatch(state);

          final posSlot =
              _posSlotDecoder[Base.getLenToPosState(len)].decode(_rangeDecoder);
          if (posSlot >= Base.kStartPosModelIndex) {
            final numDirectBits = (posSlot >> 1) - 1;
            rep0 = (2 | (posSlot & 1)) << numDirectBits;

            if (posSlot < Base.kEndPosModelIndex) {
              rep0 += BitTreeDecoder.reverseDecode2(_posDecoders,
                  rep0 - posSlot - 1, _rangeDecoder, numDirectBits);
            } else {
              rep0 += _rangeDecoder
                      .decodeDirectBits(numDirectBits - Base.kNumAlignBits) <<
                  Base.kNumAlignBits;
              rep0 += _posAlignDecoder.reverseDecode(_rangeDecoder);
              if (rep0 < 0) {
                if (rep0 == -1) {
                  break;
                }
                return false;
              }
            }
          } else {
            rep0 = posSlot;
          }
        }

        if ((rep0 >= nowPos64) || (rep0 >= _dictionarySizeCheck)) {
          return false;
        }

        _outWindow.copyBlock(rep0, len);
        nowPos64 += len;
        prevByte = _outWindow.getByte(0);
      }
    }

    _outWindow
      ..flush()
      ..releaseStream();
    _rangeDecoder.releaseStream();

    return true;
  }

  bool setDecoderProperties(List<int> properties) {
    if (properties.length < 5) {
      return false;
    }

    var value = properties[0];
    final lc = value % 9;
    value = value ~/ 9;
    final lp = value % 5;
    final pb = value ~/ 5;

    if (!_setLcLpPb(lc, lp, pb)) {
      return false;
    }

    var dictionarySize = 0;
    for (var i = 0; i < 4; ++i) {
      // ignore: avoid_as
      dictionarySize += properties[i + 1] * (math.pow(2, 8 * i) as int);
    }

    return _setDictionarySize(dictionarySize);
  }
}
