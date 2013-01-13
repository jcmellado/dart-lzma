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
  final propertiesSize = 5;

  var properties = new List<int>(propertiesSize);
  if (inStream.readBlock(properties, 0, propertiesSize) != propertiesSize) {
    throw new Exception("Input .lzma file is too short");
  }

  var decoder = new Decoder();
  if (!decoder.setDecoderProperties(properties)) {
    throw "Incorrect stream properties";
  }

  var outSize = 0;
  for (var i = 0; i < 8; ++ i){
    var value = inStream.read();
    if (value < 0) {
      throw new Exception("Can't read stream size");
    }
    outSize += value * math.pow(2, 8 * i);
  }

  if (!decoder.decode(inStream, outStream, outSize)) {
    throw "Error in data stream";
  }

  return true;
}

class OutWindow {
  List<int> _buffer;
  int _pos;
  int _windowSize = 0;
  int _streamPos;
  OutStream _stream;

  void create(int windowSize) {
    if ((_buffer == null) || (_windowSize != windowSize)) {
      _buffer = new List<int>(windowSize);
    }

    _windowSize = windowSize;
    _pos = 0;
    _streamPos = 0;
  }

  void setStream(OutStream stream) {
    releaseStream();
    _stream = stream;
  }

  void releaseStream() {
    flush();
    _stream = null;
  }

  void init(bool solid) {
    if (!solid) {
      _streamPos = 0;
      _pos = 0;
    }
  }

  void flush() {
    var size = _pos - _streamPos;
    if (size != 0) {
      _stream.writeBlock(_buffer, _streamPos, size);

      if (_pos >= _windowSize) {
        _pos = 0;
      }
      _streamPos = _pos;
    }
  }

  void copyBlock(int distance, int len) {
    var pos = _pos - distance - 1;
    if (pos < 0) {
      pos += _windowSize;
    }

    for (var i = 0; i < len; ++ i) {
      if (pos >= _windowSize) {
        pos = 0;
      }

      _buffer[_pos ++] = _buffer[pos ++];

      if (_pos >= _windowSize) {
        flush();
      }
    }
  }

  void putByte(int b) {
    _buffer[_pos ++] = b;

    if (_pos >= _windowSize) {
      flush();
    }
  }

  int getByte(int distance) {
    var pos = _pos - distance - 1;
    if (pos < 0) {
      pos += _windowSize;
    }
    return _buffer[pos];
  }
}

class RangeDecoder {
  static final int _kTopMask = 0xff000000;

  static final int _kNumBitModelTotalBits = 11;
  static final int _kBitModelTotal = 1 << _kNumBitModelTotalBits;
  static final int _kNumMoveBits = 5;

  var _range;
  var _code;

  InStream _stream;

  void setStream(InStream stream) {
    _stream = stream;
  }

  void releaseStream() {
    _stream = null;
  }

  void init() {
    _code = 0;
    _range = -1;

    for (var i = 0; i < 5; ++ i) {
      _code = (_code << 8) | _stream.read();
    }
  }

  int decodeDirectBits(int numTotalBits) {
    var result = 0;

    for (var i = numTotalBits; i > 0; -- i) {
      _range = (_range >> 1) & 0x7fffffff;
      var t = ((_code - _range) >> 31) & 1;
      _code -= _range & (t - 1);
      result = (result << 1) | (1 - t);

      if ((_range & _kTopMask) == 0) {
        _code = (_code << 8) | _stream.read();
        _range <<= 8;
      }
    }

    return result;
  }

  int decodeBit(List<int> probs, int index) {
    var prob = probs[index];

    var newBound = ((_range >>_kNumBitModelTotalBits) & 0x1fffff) * prob;

    if ((new int32.fromInt(_code) ^ 0x80000000) < (new int32.fromInt(newBound) ^ 0x80000000)) {
      _range = newBound;
      probs[index] = prob + ((_kBitModelTotal - prob) >> _kNumMoveBits);

      if ((_range & _kTopMask) == 0) {
        _code = (_code << 8) | _stream.read();
        _range <<= 8;
      }

      return 0;
    }

    _range -= newBound;
    _code -= newBound;
    probs[index] = prob - ((prob >> _kNumMoveBits) & 0x7ffffff);

    if ((_range & _kTopMask) == 0) {
      _code = (_code << 8) | _stream.read();
      _range <<= 8;
    }

    return 1;
  }

  static void initBitModels(List<int> probs) {
    for (var i = 0; i < probs.length; ++ i) {
      probs[i] = _kBitModelTotal >> 1;
    }
  }
}

class BitTreeDecoder {
  final List<int> _models;
  final int _numBitLevels;

  BitTreeDecoder(int numBitLevels)
    : _numBitLevels = numBitLevels,
      _models = new List<int>(1 << numBitLevels);

  void init() {
    RangeDecoder.initBitModels(_models);
  }

  int decode(RangeDecoder rangeDecoder) {
    var m = 1;

    for (var i = _numBitLevels; i > 0; -- i) {
      m = (m << 1) | rangeDecoder.decodeBit(_models, m);
    }

    return m - (1 << _numBitLevels);
  }

  int reverseDecode(RangeDecoder rangeDecoder) {
    var m = 1, symbol = 0;

    for (var i = 0; i < _numBitLevels; ++ i) {
      var bit = rangeDecoder.decodeBit(_models, m);
      m = (m << 1) | bit;
      symbol |= bit << i;
    }

    return symbol;
  }

  static int reverseDecode2(List<int>models, int startIndex,
                            RangeDecoder rangeDecoder, int numBitLevels) {
    var m = 1, symbol = 0;

    for (var i = 0; i < numBitLevels; ++ i) {
      var bit = rangeDecoder.decodeBit(models, startIndex + m);
      m = (m << 1) | bit;
      symbol |= bit << i;
    }

    return symbol;
  }
}

class LenDecoder {
  final List<int> _choice = new List<int>(2);
  final List<BitTreeDecoder> _lowCoder = new List<BitTreeDecoder>(Base.kNumPosStatesMax);
  final List<BitTreeDecoder> _midCoder = new List<BitTreeDecoder>(Base.kNumPosStatesMax);
  final BitTreeDecoder _highCoder = new BitTreeDecoder(Base.kNumHighLenBits);
  int _numPosStates = 0;

  void create(int numPosStates) {
    for (; _numPosStates < numPosStates; ++ _numPosStates) {
      _lowCoder[_numPosStates] = new BitTreeDecoder(Base.kNumLowLenBits);
      _midCoder[_numPosStates] = new BitTreeDecoder(Base.kNumMidLenBits);
    }
  }

  void init() {
    RangeDecoder.initBitModels(_choice);

    for (var i = 0; i < _numPosStates; ++ i) {
      _lowCoder[i].init();
      _midCoder[i].init();
    }

    _highCoder.init();
  }

  int decode(RangeDecoder rangeDecoder, int posState) {
    if (rangeDecoder.decodeBit(_choice, 0) == 0) {
      return _lowCoder[posState].decode(rangeDecoder);
    }

    if (rangeDecoder.decodeBit(_choice, 1) == 0) {
      return Base.kNumLowLenSymbols + _midCoder[posState].decode(rangeDecoder);
    }

    return Base.kNumLowLenSymbols + Base.kNumMidLenSymbols + _highCoder.decode(rangeDecoder);
  }
}

class Decoder2 {
  final List<int> _decoders = new List<int>(0x300);

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

    do {
      var matchBit = (matchByte >> 7) & 1;
      matchByte <<= 1;

      var bit = rangeDecoder.decodeBit(_decoders, ((1 + matchBit) << 8) + symbol);
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
  List<Decoder2> _coders;
  int _numPrevBits;
  int _numPosBits;
  int _posMask;

  void create(int numPosBits, int numPrevBits) {
    if ((_coders != null) && (_numPrevBits == numPrevBits) && (_numPosBits == numPosBits)) {
      return;
    }
    _numPosBits = numPosBits;
    _posMask = (1 << numPosBits) - 1;
    _numPrevBits = numPrevBits;

    var numStates = 1 << (_numPrevBits + _numPosBits);
    _coders = new List<Decoder2>(numStates);

    for (var i = 0; i < numStates; ++ i) {
      _coders[i] = new Decoder2();
    }
  }

  void init() {
    var numStates = 1 << (_numPrevBits + _numPosBits);
    for (var i = 0; i < numStates; ++ i) {
      _coders[i].init();
    }
  }

  Decoder2 getDecoder(int pos, int prevByte) =>
    _coders[((pos & _posMask) << _numPrevBits) + ((prevByte & 0xff) >> (8 - _numPrevBits))];
}

class Decoder {
  final OutWindow _outWindow = new OutWindow();
  final RangeDecoder _rangeDecoder = new RangeDecoder();

  final List<int> _isMatchDecoders = new List<int>(Base.kNumStates << Base.kNumPosStatesBitsMax);
  final List<int> _isRepDecoders = new List<int>(Base.kNumStates);
  final List<int> _isRepG0Decoders = new List<int>(Base.kNumStates);
  final List<int> _isRepG1Decoders = new List<int>(Base.kNumStates);
  final List<int> _isRepG2Decoders = new List<int>(Base.kNumStates);
  final List<int> _isRep0LongDecoders = new List<int>(Base.kNumStates << Base.kNumPosStatesBitsMax);

  final List<BitTreeDecoder> _posSlotDecoder = new List<BitTreeDecoder>(Base.kNumLenToPosStates);
  final List<int> _posDecoders = new List<int>(Base.kNumFullDistances - Base.kEndPosModelIndex);

  final BitTreeDecoder _posAlignDecoder = new BitTreeDecoder(Base.kNumAlignBits);

  final LenDecoder _lenDecoder = new LenDecoder();
  final LenDecoder _repLenDecoder = new LenDecoder();

  final LiteralDecoder _literalDecoder = new LiteralDecoder();

  int _dictionarySize = -1;
  int _dictionarySizeCheck = -1;

  int _posStateMask;

  Decoder() {
    for (var i = 0; i < Base.kNumLenToPosStates; ++ i) {
      _posSlotDecoder[i] = new BitTreeDecoder(Base.kNumPosSlotBits);
    }
  }

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
    if ((lc > Base.kNumLitContextBitsMax) || (lp > 4) || (pb > Base.kNumPosStatesBitsMax)) {
      return false;
    }

    _literalDecoder.create(lp, lc);

    var numPosStates = 1 << pb;
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

    for (var i = 0; i < Base.kNumLenToPosStates; ++ i) {
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

    var state = Base.stateInit();
    var rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;

    var nowPos64 = 0;
    var prevByte = 0;

    while ((outSize < 0) || (nowPos64 < outSize)) {
      var posState = nowPos64 & _posStateMask;

      if (_rangeDecoder.decodeBit(_isMatchDecoders, (state << Base.kNumPosStatesBitsMax) + posState) == 0) {
        var decoder2 = _literalDecoder.getDecoder(nowPos64, prevByte);

        if (!Base.stateIsCharState(state)) {
          prevByte = decoder2.decodeWithMatchByte(_rangeDecoder, _outWindow.getByte(rep0));
        } else {
          prevByte = decoder2.decodeNormal(_rangeDecoder);
        }
        _outWindow.putByte(prevByte);

        state = Base.stateUpdateChar(state);

        ++ nowPos64;
      } else {
        var len;
        if (_rangeDecoder.decodeBit(_isRepDecoders, state) == 1) {
          len = 0;
          if (_rangeDecoder.decodeBit(_isRepG0Decoders, state) == 0) {
            if (_rangeDecoder.decodeBit(_isRep0LongDecoders, (state << Base.kNumPosStatesBitsMax) + posState) == 0) {
              state = Base.stateUpdateShortRep(state);
              len = 1;
            }
          } else {
            var distance;
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
            len = _repLenDecoder.decode(_rangeDecoder, posState) + Base.kMatchMinLen;
            state = Base.stateUpdateRep(state);
          }
        } else {
          rep3 = rep2;
          rep2 = rep1;
          rep1 = rep0;

          len = Base.kMatchMinLen + _lenDecoder.decode(_rangeDecoder, posState);
          state = Base.stateUpdateMatch(state);

          var posSlot = _posSlotDecoder[Base.getLenToPosState(len)].decode(_rangeDecoder);
          if (posSlot >= Base.kStartPosModelIndex) {

            var numDirectBits = (posSlot >> 1) - 1;
            rep0 = (2 | (posSlot & 1)) << numDirectBits;

            if (posSlot < Base.kEndPosModelIndex) {
              rep0 += BitTreeDecoder.reverseDecode2(_posDecoders,
                  rep0 - posSlot - 1, _rangeDecoder, numDirectBits);
            } else {
              rep0 += _rangeDecoder.decodeDirectBits(numDirectBits - Base.kNumAlignBits) << Base.kNumAlignBits;
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

    _outWindow.flush();
    _outWindow.releaseStream();
    _rangeDecoder.releaseStream();

    return true;
  }

  bool setDecoderProperties(List<int> properties) {
    if (properties.length < 5) {
      return false;
    }

    var value = properties[0];
    var lc = value % 9;
    value = value ~/ 9;
    var lp = value % 5;
    var pb = value ~/ 5;

    if (!_setLcLpPb(lc, lp, pb)) {
      return false;
    }

    var dictionarySize = 0;
    for (var i = 0; i < 4; ++ i) {
      dictionarySize += properties[i + 1] * math.pow(2, 8 * i);
    }

    return _setDictionarySize(dictionarySize);
  }
}
