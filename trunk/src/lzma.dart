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

#library("lzma");

interface InStream {
  int readByte();
  
  int get length();
}

interface OutStream {
  void writeByte(final int value);
  
  int get length();
}

bool decompress(final InStream inStream, final OutStream outStream) {
  final Decoder decoder = new Decoder();

  if ( !decoder.setDecoderProperties(inStream) ) {
    throw "Incorrect stream properties";
  }

  int outSize = inStream.readByte();
  outSize |= inStream.readByte() << 8;
  outSize |= inStream.readByte() << 16;
  outSize += inStream.readByte() * 16777216;
  
  inStream.readByte();
  inStream.readByte();
  inStream.readByte();
  inStream.readByte();
  
  if ( !decoder.decode(inStream, outStream, outSize) ) {
    throw "Error in data stream";
  }

  return true;
}

class Base {
  static final int kNumRepDistances = 4;
  static final int kNumStates = 12;
  
  static int stateInit() => 0;
  
  static int stateUpdateChar(final int index) =>
      index < 4 ? 0 : (index < 10 ? index - 3 : index - 6);
  
  static int stateUpdateMatch(final int index) => index < 7 ? 7 : 10;
  
  static int stateUpdateRep(final int index) => index < 7 ? 8 : 11;
  
  static int stateUpdateShortRep(final int index) => index < 7 ? 9 : 11;

  static bool stateIsCharState(final int index) => index < 7;
  
  static final int kNumPosSlotBits = 6;
  static final int kDicLogSizeMin = 0;
  
  static final int kNumLenToPosStatesBits = 2;
  static final int kNumLenToPosStates = 1 << kNumLenToPosStatesBits;
  
  static final int kMatchMinLen = 2;
  
  static int getLenToPosState(final int len) =>
     len - kMatchMinLen < kNumLenToPosStates ? len - kMatchMinLen : kNumLenToPosStates - 1;  
  
  static final int kNumAlignBits = 4;
  static final int kAlignTableSize = 1 << kNumAlignBits;
  static final int kAlignMask = kAlignTableSize - 1;
  
  static final int kStartPosModelIndex = 4;
  static final int kEndPosModelIndex = 14;
  static final int kNumPosModels = kEndPosModelIndex - kStartPosModelIndex;
  
  static final int kNumFullDistances = 1 << (kEndPosModelIndex >> 1);
  
  static final int kNumLitPosStatesBitsEncodingMax = 4;
  static final int kNumLitContextBitsMax = 8;
  
  static final int kNumPosStatesBitsMax = 4;
  static final int kNumPosStatesMax = 1 << kNumPosStatesBitsMax;
  static final int kNumPosStatesBitsEncodingMax = 4;
  static final int kNumPosStatesEncodingMax = 1 << kNumPosStatesBitsEncodingMax;
  
  static final int kNumLowLenBits = 3;
  static final int kNumMidLenBits = 3;
  static final int kNumHighLenBits = 8;
  static final int kNumLowLenSymbols = 1 << kNumLowLenBits;
  static final int kNumMidLenSymbols = 1 << kNumMidLenBits;
  static final int kNumLenSymbols =
      kNumLowLenSymbols + kNumMidLenSymbols + (1 << kNumHighLenBits);
   
  static final int kMatchMaxLen = kMatchMinLen + kNumLenSymbols - 1;
}

class OutWindow {
  List<int> _buffer;
  int _pos;
  int _windowSize = 0;
  int _streamPos;
  OutStream _stream;
    
  void create(final int windowSize) {
    if ( (null == _buffer) || (_windowSize !== windowSize) ) {
      _buffer = new List<int>(windowSize);
    }
    
    _windowSize = windowSize;
    _pos = 0;
    _streamPos = 0;
  }

  void setStream(final OutStream stream) {
    releaseStream();
    _stream = stream;
  }

  void releaseStream() {
    flush();
    _stream = null;
  }

  void init(final bool solid) {
    if (!solid) {
      _streamPos = 0;
      _pos = 0;
    }
  }

  void flush() {
    final int size = _pos - _streamPos;
    if (0 !== size) {
      
      for (int i = 0; i < size; ++ i) {
        _stream.writeByte(_buffer[_streamPos ++]);
      }
      
      if (_pos >= _windowSize) {
        _pos = 0;
      }
      
      _streamPos = _pos;
    }
  }

  void copyBlock(final int distance, final int len) {
    int pos = _pos - distance - 1;
    
    if (pos < 0) {
      pos += _windowSize;
    }
    
    for (int i = 0; i < len; ++ i) {
      
      if (pos >= _windowSize) {
        pos = 0;
      }
      
      _buffer[_pos ++] = _buffer[pos ++];
      
      if (_pos >= _windowSize) {
        flush();
      }
    }
  }

  void putByte(final int b) {
    _buffer[_pos ++] = b;
    
    if (_pos >= _windowSize) {
      flush();
    }
  }

  int getByte(final int distance) {
    int pos = _pos - distance - 1;
    
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
  
  int _range;
  int _code;

  InStream _stream;
  
  void setStream(final InStream stream) {
    _stream = stream;
  }

  void releaseStream() {
    _stream = null;
  }
  
  void init() {
    _code = 0;
    _range = -1;
    
    for (int i = 0; i < 5; ++ i) {
      _code = (_code << 8) | _stream.readByte();
    }
  }

  int decodeDirectBits(final int numTotalBits) {
    int result = 0;

    for (int i = numTotalBits; i !== 0; -- i) {
      _range = (_range >> 1) & 0x7fffffff;
      final int t = ( (_code - _range) >> 31) & 0x1;
      _code -= _range & (t - 1);
      result = (result << 1) | (1 - t);

      if ( (_range & _kTopMask) === 0) {
        _code = (_code << 8) | _stream.readByte();
        _range <<= 8;
      }
    }

    return result;
  }

  int decodeBit(final List<int> probs, final int index) {
    final int prob = probs[index];

    final int newBound = ( (_range >> _kNumBitModelTotalBits) & 0x1fffff) * prob;

    if ( (_code ^ 0x80000000) < (newBound ^ 0x80000000) ) {
      _range = newBound;
      probs[index] = prob + ( ( (_kBitModelTotal - prob) >> _kNumMoveBits) & 0x7ffffff);
      
      if ( (_range & _kTopMask) === 0) {
        _code = (_code << 8) | _stream.readByte();
        _range <<= 8;
      }
      
      return 0;
    }

    _range -= newBound;
    _code -= newBound;
    probs[index] = prob - ( (prob >> _kNumMoveBits) & 0x7ffffff);
    
    if ( (_range & _kTopMask) === 0) {
      _code = (_code << 8) | _stream.readByte();
      _range <<= 8;
    }
 
    return 1;
  }

  static void initBitModels(final List<int> probs) {
    for (int i = 0; i < probs.length; ++ i) {
      probs[i] = _kBitModelTotal >> 1;
    }
  }
}

class BitTreeDecoder {
  List<int> _models;
  int _numBitLevels;
  
  BitTreeDecoder(final int numBitLevels) {
    _numBitLevels = numBitLevels;
    _models = new List<int>(1 << numBitLevels);
  }
  
  void init() {
    RangeDecoder.initBitModels(_models);
  }

  int decode(final RangeDecoder rangeDecoder) {
    int m = 1;

    for (int i = _numBitLevels; i !== 0; -- i) {
      m = (m << 1) | rangeDecoder.decodeBit(_models, m);
    }
    
    return m - (1 << _numBitLevels);
  }

  int reverseDecode(final RangeDecoder rangeDecoder) {
    int m = 1, symbol = 0;

    for (int i = 0; i < _numBitLevels; ++ i) {
      final int bit = rangeDecoder.decodeBit(_models, m);
      m = (m << 1) | bit;
      symbol |= bit << i;
    }
    
    return symbol;
  }

  static int reverseDecode2(final List<int>models, final int startIndex,
                            final RangeDecoder rangeDecoder, final int numBitLevels) {
    int m = 1, symbol = 0;

    for (int i = 0; i < numBitLevels; ++ i) {
      final int bit = rangeDecoder.decodeBit(models, startIndex + m);
      m = (m << 1) | bit;
      symbol |= bit << i;
    }
    
    return symbol;
  }
}

class LenDecoder {
  List<int> _choice;
  List<BitTreeDecoder> _lowCoder;
  List<BitTreeDecoder> _midCoder;
  BitTreeDecoder _highCoder;
  int _numPosStates = 0;
  
  LenDecoder() {
    _choice = new List<int>(2);
    _lowCoder = new List<BitTreeDecoder>(Base.kNumPosStatesMax);
    _midCoder = new List<BitTreeDecoder>(Base.kNumPosStatesMax);
    _highCoder = new BitTreeDecoder(Base.kNumHighLenBits);
  }
  
  void create(final int numPosStates) {
    for (; _numPosStates < numPosStates; ++ _numPosStates) {
      _lowCoder[_numPosStates] = new BitTreeDecoder(Base.kNumLowLenBits);
      _midCoder[_numPosStates] = new BitTreeDecoder(Base.kNumMidLenBits);
    }
  }

  void init() {
    RangeDecoder.initBitModels(_choice);
    
    for(int i = 0; i < _numPosStates; ++ i) {
      _lowCoder[i].init();
      _midCoder[i].init();
    }
    
    _highCoder.init();
  }

  int decode(final RangeDecoder rangeDecoder, final int posState) {
    if (rangeDecoder.decodeBit(_choice, 0) === 0) {
      return _lowCoder[posState].decode(rangeDecoder);
    }
    
    if (rangeDecoder.decodeBit(_choice, 1) === 0) {
      return Base.kNumLowLenSymbols + _midCoder[posState].decode(rangeDecoder);
    }
    
    return Base.kNumLowLenSymbols + Base.kNumMidLenSymbols + _highCoder.decode(rangeDecoder);
  }
}

class Decoder2 {
  List<int> _decoders;
  
  Decoder2() {
    _decoders = new List<int>(0x300);
  }
  
  void init() {
    RangeDecoder.initBitModels(_decoders);
  }
  
  int decodeNormal(final RangeDecoder rangeDecoder) {
    int symbol = 1;

    do {
      symbol = (symbol << 1) | rangeDecoder.decodeBit(_decoders, symbol);
    } while(symbol < 0x100);

    return symbol & 0xff;
  }

  int decodeWithMatchByte(final RangeDecoder rangeDecoder, int matchByte) {
    int symbol = 1;

    do {
      final int matchBit = (matchByte >> 7) & 1;
      matchByte <<= 1;
      
      final int bit = rangeDecoder.decodeBit(_decoders, ( (1 + matchBit) << 8) + symbol);
      symbol = (symbol << 1) | bit;
      
      if (matchBit !== bit) {
        while (symbol < 0x100) {
          symbol = (symbol << 1) | rangeDecoder.decodeBit(_decoders, symbol);
        }
        break;
      }
      
    } while(symbol < 0x100);

    return symbol & 0xff;
  }
}

class LiteralDecoder {
  List<Decoder2> _coders;
  int _numPrevBits;
  int _numPosBits;
  int _posMask;

  void create(final int numPosBits, final int numPrevBits) {
    if ( (null != _coders) &&
        (_numPrevBits === numPrevBits) &&
        (_numPosBits === numPosBits) ) {
      return;
    }
    _numPosBits = numPosBits;
    _posMask = (1 << numPosBits) - 1;
    _numPrevBits = numPrevBits;

    final int numStates = 1 << (_numPrevBits + _numPosBits);
    _coders = new List<Decoder2>(numStates);

    for (int i = 0; i < numStates; ++ i) {
      _coders[i] = new Decoder2();
    }
  }

  void init() {
    final int numStates = 1 << (_numPrevBits + _numPosBits);
    for (int i = 0; i < numStates; ++ i) {
      _coders[i].init();
    }
  }

  Decoder2 getDecoder(final int pos, final int prevByte) {
    return _coders[( (pos & _posMask) << _numPrevBits)
        + ( (prevByte & 0xff) >> (8 - _numPrevBits) )];
  }
}

class Decoder {
  OutWindow _outWindow;
  RangeDecoder _rangeDecoder;

  List<int> _isMatchDecoders;
  List<int> _isRepDecoders;
  List<int> _isRepG0Decoders;
  List<int> _isRepG1Decoders;
  List<int> _isRepG2Decoders;
  List<int> _isRep0LongDecoders;
  
  List<BitTreeDecoder> _posSlotDecoder;
  List<int> _posDecoders;
  
  BitTreeDecoder _posAlignDecoder;
    
  LenDecoder _lenDecoder;
  LenDecoder _repLenDecoder;

  LiteralDecoder _literalDecoder;

  int _dictionarySize = -1;
  int _dictionarySizeCheck = -1;
  
  int _posStateMask;
  
  Decoder() {
    _outWindow = new OutWindow();
    _rangeDecoder = new RangeDecoder();

    _isMatchDecoders = new List<int>(Base.kNumStates << Base.kNumPosStatesBitsMax);
    _isRepDecoders = new List<int>(Base.kNumStates);
    _isRepG0Decoders = new List<int>(Base.kNumStates);
    _isRepG1Decoders = new List<int>(Base.kNumStates);
    _isRepG2Decoders = new List<int>(Base.kNumStates);
    _isRep0LongDecoders = new List<int>(Base.kNumStates << Base.kNumPosStatesBitsMax);
    
    _posSlotDecoder = new List<BitTreeDecoder>(Base.kNumLenToPosStates);
    _posDecoders = new List<int>(Base.kNumFullDistances - Base.kEndPosModelIndex);
    
    _posAlignDecoder = new BitTreeDecoder(Base.kNumAlignBits);
    
    _lenDecoder = new LenDecoder();
    _repLenDecoder = new LenDecoder();
    
    _literalDecoder = new LiteralDecoder();
    
    for (int i = 0; i < Base.kNumLenToPosStates; ++ i) {
      _posSlotDecoder[i] = new BitTreeDecoder(Base.kNumPosSlotBits);
    }
  }
  
  bool _setDictionarySize(final int dictionarySize) {
    if (dictionarySize < 0) {
      return false;
    }
    
    if (_dictionarySize !== dictionarySize) {
      _dictionarySize = dictionarySize;
      _dictionarySizeCheck = Math.max(_dictionarySize, 1);
      _outWindow.create( Math.max(_dictionarySizeCheck, 4096) );
    }
    
    return true;
  }

  bool _setLcLpPb(final int lc, final int lp, final int pb) {
    if (lc > Base.kNumLitContextBitsMax || lp > 4 || pb > Base.kNumPosStatesBitsMax) {
      return false;
    }

    _literalDecoder.create(lp, lc);

    final int numPosStates = 1 << pb;
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

    for (int i = 0; i < Base.kNumLenToPosStates; ++ i) {
      _posSlotDecoder[i].init();
    }

    _lenDecoder.init();
    _repLenDecoder.init();
    _posAlignDecoder.init();
    _rangeDecoder.init();
  }
  
  bool decode(final InStream inStream, final OutStream outStream, final int outSize) {
    _rangeDecoder.setStream(inStream);
    _outWindow.setStream(outStream);

    init();

    int state = Base.stateInit();
    int rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;
    
    int nowPos64 = 0;
    int prevByte = 0;
    
    while (outSize < 0 || nowPos64 < outSize) {
      final int posState = nowPos64 & _posStateMask;

      if (_rangeDecoder.decodeBit(_isMatchDecoders, (state << Base.kNumPosStatesBitsMax) + posState) === 0) {
        final Decoder2 decoder2 = _literalDecoder.getDecoder(nowPos64, prevByte);

        if ( !Base.stateIsCharState(state) ) {
          prevByte = decoder2.decodeWithMatchByte(_rangeDecoder, _outWindow.getByte(rep0) );
        } else {
          prevByte = decoder2.decodeNormal(_rangeDecoder);
        }
        _outWindow.putByte(prevByte);

        state = Base.stateUpdateChar(state);
        
        ++ nowPos64;
      } else {
        int len;
        if (_rangeDecoder.decodeBit(_isRepDecoders, state) === 1) {
          len = 0;
          if (_rangeDecoder.decodeBit(_isRepG0Decoders, state) === 0) {
            if (_rangeDecoder.decodeBit(_isRep0LongDecoders, (state << Base.kNumPosStatesBitsMax) + posState) === 0) {
              state = Base.stateUpdateShortRep(state);
              len = 1;
            }
          } else {
            int distance;
            if (_rangeDecoder.decodeBit(_isRepG1Decoders, state) === 0) {
              distance = rep1;
            } else {
              if (_rangeDecoder.decodeBit(_isRepG2Decoders, state) === 0) {
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
          if (0 === len) {
            len = _repLenDecoder.decode(_rangeDecoder, posState) + Base.kMatchMinLen;
            state = Base.stateUpdateRep(state);
          }
        } else {
          rep3 = rep2;
          rep2 = rep1;
          rep1 = rep0;

          len = Base.kMatchMinLen + _lenDecoder.decode(_rangeDecoder, posState);
          state = Base.stateUpdateMatch(state);

          final int posSlot = _posSlotDecoder[Base.getLenToPosState(len)].decode(_rangeDecoder);
          if (posSlot >= Base.kStartPosModelIndex) {

            final int numDirectBits = (posSlot >> 1) - 1;
            rep0 = (2 | (posSlot & 1) ) << numDirectBits;

            if (posSlot < Base.kEndPosModelIndex) {
              rep0 += BitTreeDecoder.reverseDecode2(_posDecoders,
                  rep0 - posSlot - 1, _rangeDecoder, numDirectBits);
            } else {
              rep0 += _rangeDecoder.decodeDirectBits(numDirectBits - Base.kNumAlignBits) << Base.kNumAlignBits;
              rep0 += _posAlignDecoder.reverseDecode(_rangeDecoder);
              if (rep0 < 0) {
                if (rep0 === -1) {
                  break;
                }
                return false;
              }
            }
          } else {
            rep0 = posSlot;
          }
        }

        if (rep0 >= nowPos64 || rep0 >= _dictionarySizeCheck) {
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
  
  bool setDecoderProperties(final InStream properties) {
    if (properties.length < 5) {
      return false;
    }

    int value = properties.readByte();
    final int lc = value % 9;
    value = value ~/ 9;
    final int lp = value % 5;
    final int pb = value ~/ 5;
    
    if ( !_setLcLpPb(lc, lp, pb) ) {
      return false;
    }

    int dictionarySize = properties.readByte();
    dictionarySize |= properties.readByte() << 8;
    dictionarySize |= properties.readByte() << 16;
    dictionarySize += properties.readByte() * 16777216;

    return _setDictionarySize(dictionarySize);
  }
}
