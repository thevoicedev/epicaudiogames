// Java's Double.toString (JDK 17's FloatingDecimal), which Kotlin's Double.toString is: Expr.kt's text and key.

/**
 * JDK 17's FloatingDecimal.BinaryToASCIIBuffer, digit for digit. Its digits aren't always the shortest that read back
 * (4.9E-324 for Double.MIN_VALUE, 1.58E-322, 9.999999999999999E22 for 1e23), so the Swift engine can't take them from
 * Swift's own shortest form.
 */
enum JavaDoubleString {
    /// Double.toString(d) for a finite, non-zero d.
    static func string(_ d: Double) -> String {
        let bits = d.bitPattern
        var fractBits = Int64(bitPattern: bits & signifMask)
        var binExp = Int(Int64(bitPattern: (bits & expMask) >> UInt64(expShift)))
        let nSignificantBits: Int
        if binExp == 0 {
            // A subnormal: move its top bit up to where a normal number's hidden bit is.
            let leadingZeros = fractBits.leadingZeroBitCount
            let shift = leadingZeros - (63 - expShift)
            fractBits <<= Int64(shift)
            binExp = 1 - shift
            nSignificantBits = 64 - leadingZeros
        } else {
            fractBits |= fractHOB
            nSignificantBits = expShift + 1
        }
        binExp -= expBias
        var buffer = Buffer()
        buffer.dtoa(binExp, fractBits, nSignificantBits)
        return (bits & signMask != 0 ? "-" : "") + buffer.chars()
    }

    static let expShift = 52
    static let fractHOB: Int64 = 1 << 52
    static let expOne: UInt64 = 1023 << 52
    static let expBias = 1023
    static let signifMask: UInt64 = 0x000F_FFFF_FFFF_FFFF
    static let expMask: UInt64 = 0x7FF0_0000_0000_0000
    static let signMask: UInt64 = 0x8000_0000_0000_0000
    static let maxSmallBinExp = 62
    static let minSmallBinExp = -(63 / 3)

    /// 5^0 ... 5^26 (FDBigInteger.LONG_5_POW).
    static let long5Pow: [Int64] = (0..<27).map { n in (0..<n).reduce(Int64(1)) { p, _ in p * 5 } }

    /// 5^0 ... 5^13 (FDBigInteger.SMALL_5_POW).
    static let small5Pow: [Int32] = (0..<14).map { n in (0..<n).reduce(Int32(1)) { p, _ in p * 5 } }

    /// About ceil(log2(5^i)).
    static let n5Bits: [Int] = [0, 3, 5, 7, 10, 12, 14, 17, 19, 21, 24, 26, 28, 31, 33, 35, 38, 40, 42, 45, 47, 49, 52,
                                54, 56, 59, 61]

    static let insignificantDigitsNumber: [Int] = [
        0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 9, 10, 10,
        10, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 14, 14, 14, 15, 15, 15, 15, 16, 16, 16, 17, 17, 17, 18, 18, 18, 19,
    ]

    static func insignificantDigitsForPow2(_ p2: Int) -> Int {
        p2 > 1 && p2 < insignificantDigitsNumber.count ? insignificantDigitsNumber[p2] : 0
    }

    /// FloatingDecimal's estimate of floor(log10(d)), from a cheap guess at log10 of the mantissa.
    static func estimateDecExp(_ fractBits: Int64, _ binExp: Int) -> Int {
        let d2 = Double(bitPattern: expOne | (UInt64(bitPattern: fractBits) & signifMask))
        let d = ((d2 - 1.5) * 0.289529654 + 0.176091259) + Double(binExp) * 0.301029995663981
        let dBits = d.bitPattern
        let exponent = Int((dBits & expMask) >> UInt64(expShift)) - expBias
        let isNegative = dBits & signMask != 0
        if exponent >= 0 && exponent < 52 {
            let mask = signifMask >> UInt64(exponent)
            let r = Int(Int32(truncatingIfNeeded: ((dBits & signifMask) | UInt64(fractHOB)) >> UInt64(expShift - exponent)))
            return isNegative ? ((mask & dBits) == 0 ? -r : -r - 1) : r
        } else if exponent < 0 {
            return (dBits & ~signMask) == 0 ? 0 : (isNegative ? -1 : 0)
        } else {
            return Int(Int32(truncatingIfNeeded: Int64(d)))
        }
    }

    /// The digits and decimal exponent of one number (BinaryToASCIIBuffer).
    struct Buffer {
        var digits = [UInt8](repeating: 0, count: 20)
        var decExponent = 0
        var firstDigitIndex = 0
        var nDigits = 0

        /// All the significant bits fit a Long: write its digits, rounding off the ones that mean nothing.
        mutating func developLongDigits(_ decExponent0: Int, _ lvalue0: Int64, _ insignificantDigits: Int) {
            var decExponent = decExponent0
            var lvalue = lvalue0
            if insignificantDigits != 0 {
                let pow10 = JavaDoubleString.long5Pow[insignificantDigits] << Int64(insignificantDigits)
                let residue = lvalue % pow10
                lvalue /= pow10
                decExponent += insignificantDigits
                if residue >= (pow10 >> 1) { lvalue += 1 }
            }
            var digitno = digits.count - 1
            var c = Int(lvalue % 10)
            lvalue /= 10
            while c == 0 {
                decExponent += 1
                c = Int(lvalue % 10)
                lvalue /= 10
            }
            while lvalue != 0 {
                digits[digitno] = UInt8(c) + 0x30
                digitno -= 1
                decExponent += 1
                c = Int(lvalue % 10)
                lvalue /= 10
            }
            digits[digitno] = UInt8(c) + 0x30
            self.decExponent = decExponent + 1
            firstDigitIndex = digitno
            nDigits = digits.count - digitno
        }

        mutating func dtoa(_ binExp: Int, _ fractBits0: Int64, _ nSignificantBits: Int) {
            var fractBits = fractBits0
            let tailZeros = fractBits.trailingZeroBitCount
            let nFractBits = JavaDoubleString.expShift + 1 - tailZeros
            let nTinyBits = Swift.max(0, nFractBits - binExp - 1)
            if binExp <= JavaDoubleString.maxSmallBinExp && binExp >= JavaDoubleString.minSmallBinExp {
                if nTinyBits < JavaDoubleString.long5Pow.count && nFractBits + JavaDoubleString.n5Bits[nTinyBits] < 64 {
                    if nTinyBits == 0 {
                        let insignificant = binExp > nSignificantBits
                            ? JavaDoubleString.insignificantDigitsForPow2(binExp - nSignificantBits - 1) : 0
                        if binExp >= JavaDoubleString.expShift {
                            fractBits <<= Int64(binExp - JavaDoubleString.expShift)
                        } else {
                            fractBits = Int64(bitPattern: UInt64(bitPattern: fractBits) >> UInt64(JavaDoubleString.expShift - binExp))
                        }
                        developLongDigits(0, fractBits, insignificant)
                        return
                    }
                }
            }
            // The hard case: d = (B / S) * 10^decExp with 1 <= B / S < 10, and M half an ULP scaled as B is.
            var decExp = JavaDoubleString.estimateDecExp(fractBits, binExp)
            let B5 = Swift.max(0, -decExp)
            var B2 = B5 + nTinyBits + binExp
            let S5 = Swift.max(0, decExp)
            var S2 = S5 + nTinyBits
            let M5 = B5
            var M2 = B2 - nSignificantBits

            fractBits = Int64(bitPattern: UInt64(bitPattern: fractBits) >> UInt64(tailZeros))
            B2 -= nFractBits - 1
            let common2factor = Swift.min(B2, S2)
            B2 -= common2factor
            S2 -= common2factor
            M2 -= common2factor
            // For exact powers of two the next number down is only half as far away.
            if nFractBits == 1 { M2 -= 1 }
            if M2 < 0 {
                B2 -= M2
                S2 -= M2
                M2 = 0
            }

            var ndigit = 0
            var low: Bool
            var high: Bool
            var lowDigitDifference: Int64
            var q: Int
            let n5 = JavaDoubleString.n5Bits
            let Bbits = nFractBits + B2 + (B5 < n5.count ? n5[B5] : B5 * 3)
            let tenSbits = S2 + 1 + ((S5 + 1) < n5.count ? n5[S5 + 1] : (S5 + 1) * 3)
            if Bbits < 64 && tenSbits < 64 {
                if Bbits < 32 && tenSbits < 32 {
                    // They're all Ints (with Java's wrapping).
                    let p5 = JavaDoubleString.small5Pow
                    var b = (Int32(truncatingIfNeeded: fractBits) &* p5[B5]) << Int32(B2)
                    let s = p5[S5] << Int32(S2)
                    var m = p5[M5] << Int32(M2)
                    let tens = s &* 10
                    q = Int(b / s)
                    b = 10 &* (b % s)
                    m = m &* 10
                    low = b < m
                    high = b &+ m > tens
                    if q == 0 && !high {
                        decExp -= 1
                    } else {
                        digits[ndigit] = UInt8(q) + 0x30
                        ndigit += 1
                    }
                    // Java always writes a digit after the point: E-form needs more than one digit.
                    if decExp < -3 || decExp >= 8 {
                        high = false
                        low = false
                    }
                    while !low && !high {
                        q = Int(b / s)
                        b = 10 &* (b % s)
                        m = m &* 10
                        if m > 0 {
                            low = b < m
                            high = b &+ m > tens
                        } else {
                            low = true
                            high = true
                        }
                        digits[ndigit] = UInt8(q) + 0x30
                        ndigit += 1
                    }
                    lowDigitDifference = Int64((b << 1) &- tens)
                } else {
                    // They're all Longs.
                    let p5 = JavaDoubleString.long5Pow
                    var b = (fractBits &* p5[B5]) << Int64(B2)
                    let s = p5[S5] << Int64(S2)
                    var m = p5[M5] << Int64(M2)
                    let tens = s &* 10
                    q = Int(b / s)
                    b = 10 &* (b % s)
                    m = m &* 10
                    low = b < m
                    high = b &+ m > tens
                    if q == 0 && !high {
                        decExp -= 1
                    } else {
                        digits[ndigit] = UInt8(q) + 0x30
                        ndigit += 1
                    }
                    if decExp < -3 || decExp >= 8 {
                        high = false
                        low = false
                    }
                    while !low && !high {
                        q = Int(b / s)
                        b = 10 &* (b % s)
                        m = m &* 10
                        if m > 0 {
                            low = b < m
                            high = b &+ m > tens
                        } else {
                            low = true
                            high = true
                        }
                        digits[ndigit] = UInt8(q) + 0x30
                        ndigit += 1
                    }
                    lowDigitDifference = (b << 1) &- tens
                }
            } else {
                // FDBigInteger arithmetic (exact, so its normalising shift can be left out).
                let sVal = BigWhole.pow52(S5, S2)
                var bVal = BigWhole.mulPow52(UInt64(bitPattern: fractBits), B5, B2)
                var mVal = BigWhole.pow52(M5 + 1, M2 + 1)
                let tenSVal = BigWhole.pow52(S5 + 1, S2 + 1)
                q = bVal.quoRemIteration(sVal)
                low = bVal < mVal
                high = tenSVal <= bVal + mVal
                if q == 0 && !high {
                    decExp -= 1
                } else {
                    digits[ndigit] = UInt8(q) + 0x30
                    ndigit += 1
                }
                if decExp < -3 || decExp >= 8 {
                    high = false
                    low = false
                }
                while !low && !high {
                    q = bVal.quoRemIteration(sVal)
                    mVal.multiply(by: 10)
                    low = bVal < mVal
                    high = tenSVal <= bVal + mVal
                    digits[ndigit] = UInt8(q) + 0x30
                    ndigit += 1
                }
                if high && low {
                    bVal.shiftLeft(1)
                    lowDigitDifference = bVal < tenSVal ? -1 : (bVal == tenSVal ? 0 : 1)
                } else {
                    lowDigitDifference = 0
                }
            }
            decExponent = decExp + 1
            firstDigitIndex = 0
            nDigits = ndigit
            // The last digit is rounded by the stopping condition.
            if high {
                if low {
                    if lowDigitDifference == 0 {
                        // A tie: round to an even digit.
                        if digits[firstDigitIndex + nDigits - 1] & 1 != 0 { roundup() }
                    } else if lowDigitDifference > 0 {
                        roundup()
                    }
                } else {
                    roundup()
                }
            }
        }

        /// Adds one to the last digit, carrying.
        mutating func roundup() {
            var i = firstDigitIndex + nDigits - 1
            var q = digits[i]
            if q == 0x39 {
                while q == 0x39 && i > firstDigitIndex {
                    digits[i] = 0x30
                    i -= 1
                    q = digits[i]
                }
                if q == 0x39 {
                    decExponent += 1
                    digits[firstDigitIndex] = 0x31
                    return
                }
            }
            digits[i] = q + 1
        }

        /// The digits laid out as Double.toString does: "123.45", "0.001", "1.0E-5", "1.0E7".
        func chars() -> String {
            var out: [UInt8] = []
            let ds = digits[firstDigitIndex..<(firstDigitIndex + nDigits)]
            if decExponent > 0 && decExponent < 8 {
                let charLength = Swift.min(nDigits, decExponent)
                out += ds.prefix(charLength)
                if charLength < decExponent {
                    out += [UInt8](repeating: 0x30, count: decExponent - charLength)
                    out += [0x2E, 0x30]
                } else {
                    out.append(0x2E)
                    if charLength < nDigits { out += ds.dropFirst(charLength) } else { out.append(0x30) }
                }
            } else if decExponent <= 0 && decExponent > -3 {
                out += [0x30, 0x2E]
                out += [UInt8](repeating: 0x30, count: -decExponent)
                out += ds
            } else {
                out.append(ds.first!)
                out.append(0x2E)
                if nDigits > 1 { out += ds.dropFirst() } else { out.append(0x30) }
                out.append(0x45)
                let e: Int
                if decExponent <= 0 {
                    out.append(0x2D)
                    e = -decExponent + 1
                } else {
                    e = decExponent - 1
                }
                out += Array(String(e).utf8)
            }
            return String(decoding: out, as: UTF8.self)
        }
    }

    /// A whole number of any size: FDBigInteger's values, for the comparisons its hard case makes.
    struct BigWhole: Equatable, Comparable {
        /// Base 2^32, lowest first, with no zero at the top.
        var limbs: [UInt32]

        init(_ v: UInt64) {
            limbs = [UInt32(truncatingIfNeeded: v), UInt32(truncatingIfNeeded: v >> 32)]
            trim()
        }

        mutating func trim() {
            while limbs.last == 0 { limbs.removeLast() }
        }

        /// v * 5^p5 * 2^p2.
        static func mulPow52(_ v: UInt64, _ p5: Int, _ p2: Int) -> BigWhole {
            var r = BigWhole(v)
            var n = p5
            // 5^13 fits a UInt32.
            while n >= 13 {
                r.multiply(by: 1_220_703_125)
                n -= 13
            }
            if n > 0 { r.multiply(by: UInt32(JavaDoubleString.small5Pow[n])) }
            r.shiftLeft(p2)
            return r
        }

        static func pow52(_ p5: Int, _ p2: Int) -> BigWhole { mulPow52(1, p5, p2) }

        mutating func multiply(by m: UInt32) {
            var carry: UInt64 = 0
            for i in limbs.indices {
                let p = UInt64(limbs[i]) * UInt64(m) + carry
                limbs[i] = UInt32(truncatingIfNeeded: p)
                carry = p >> 32
            }
            if carry != 0 { limbs.append(UInt32(carry)) }
            trim()
        }

        mutating func shiftLeft(_ bits: Int) {
            guard bits > 0, !limbs.isEmpty else { return }
            let words = bits / 32
            let rest = bits % 32
            if rest != 0 {
                var carry: UInt32 = 0
                for i in limbs.indices {
                    let v = limbs[i]
                    limbs[i] = (v << UInt32(rest)) | carry
                    carry = v >> UInt32(32 - rest)
                }
                if carry != 0 { limbs.append(carry) }
            }
            if words > 0 { limbs.insert(contentsOf: [UInt32](repeating: 0, count: words), at: 0) }
        }

        static func + (a: BigWhole, b: BigWhole) -> BigWhole {
            var out: [UInt32] = []
            var carry: UInt64 = 0
            for i in 0..<Swift.max(a.limbs.count, b.limbs.count) {
                let s = UInt64(i < a.limbs.count ? a.limbs[i] : 0) + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
                out.append(UInt32(truncatingIfNeeded: s))
                carry = s >> 32
            }
            if carry != 0 { out.append(UInt32(carry)) }
            var r = BigWhole(0)
            r.limbs = out
            r.trim()
            return r
        }

        /// self - b, for b <= self.
        mutating func subtract(_ b: BigWhole) {
            var borrow: Int64 = 0
            for i in limbs.indices {
                var d = Int64(limbs[i]) - Int64(i < b.limbs.count ? b.limbs[i] : 0) - borrow
                if d < 0 {
                    d += 1 << 32
                    borrow = 1
                } else {
                    borrow = 0
                }
                limbs[i] = UInt32(d)
            }
            trim()
        }

        /// FDBigInteger.quoRemIteration: returns self / s (below 10) and leaves 10 * (self % s).
        mutating func quoRemIteration(_ s: BigWhole) -> Int {
            var q = 0
            while self >= s {
                subtract(s)
                q += 1
            }
            multiply(by: 10)
            return q
        }

        static func < (a: BigWhole, b: BigWhole) -> Bool {
            if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
            for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] {
                return a.limbs[i] < b.limbs[i]
            }
            return false
        }
    }
}
