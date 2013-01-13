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

class Base {
  static final int kNumRepDistances = 4;
  static final int kNumStates = 12;

  static int stateInit() => 0;

  static int stateUpdateChar(int index) =>
      index < 4 ? 0 : (index < 10 ? index - 3 : index - 6);

  static int stateUpdateMatch(int index) => index < 7 ? 7 : 10;

  static int stateUpdateRep(int index) => index < 7 ? 8 : 11;

  static int stateUpdateShortRep(int index) => index < 7 ? 9 : 11;

  static bool stateIsCharState(int index) => index < 7;

  static final int kNumPosSlotBits = 6;
  static final int kDicLogSizeMin = 0;

  static final int kNumLenToPosStatesBits = 2;
  static final int kNumLenToPosStates = 1 << kNumLenToPosStatesBits;

  static final int kMatchMinLen = 2;

  static int getLenToPosState(int len) =>
     len - kMatchMinLen < kNumLenToPosStates ? len - kMatchMinLen : kNumLenToPosStates - 1;

  static final int kNumAlignBits = 4;
  static final int kAlignTableSize = 1 << kNumAlignBits;
  static final int kAlignMask = kAlignTableSize - 1;

  static final int kStartPosModelIndex = 4;
  static final int kEndPosModelIndex = 14;

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
