import Foundation

/// G.711 编解码（与安卓 g711Encode / ulaw2linear / alaw2linear 同一套算法）
enum G711 {

    // MARK: 编码

    static func encode(_ pcm: UnsafePointer<Int16>, count: Int, aLaw: Bool) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            out[i] = aLaw ? linear2alaw(Int(pcm[i])) : linear2ulaw(Int(pcm[i]))
        }
        return out
    }

    static func encode(_ data: Data, aLaw: Bool) -> [UInt8] {
        let n = data.count / 2
        return data.withUnsafeBytes { raw -> [UInt8] in
            let p = raw.bindMemory(to: Int16.self)
            return encode(p.baseAddress!, count: n, aLaw: aLaw)
        }
    }

    static func linear2ulaw(_ sample0: Int) -> UInt8 {
        let BIAS = 0x84, CLIP = 32635
        var sample = sample0
        let sign = (sample >> 8) & 0x80
        if sign != 0 { sample = -sample }
        if sample > CLIP { sample = CLIP }
        sample += BIAS
        var exponent = 7
        var expMask = 0x4000
        while (sample & expMask) == 0 && exponent > 0 {
            exponent -= 1
            expMask >>= 1
        }
        let mantissa = (sample >> (exponent + 3)) & 0x0F
        return UInt8(~(sign | (exponent << 4) | mantissa) & 0xFF)
    }

    static func linear2alaw(_ sample0: Int) -> UInt8 {
        let CLIP = 32635
        var sample = sample0
        let sign = (sample >> 8) & 0x80
        if sign != 0 { sample = -sample }
        if sample > CLIP { sample = CLIP }
        var exponent: Int
        if sample >= 256 {
            exponent = 7
            var expMask = 0x4000
            while (sample & expMask) == 0 && exponent > 0 {
                exponent -= 1
                expMask >>= 1
            }
            sample >>= (exponent + 3)
        } else {
            exponent = 0
            sample >>= 4
        }
        let mantissa = sample & 0x0F
        return UInt8(((sign ^ 0x55) | (exponent << 4) | mantissa) & 0xFF)
    }

    // MARK: 解码

    static func ulaw2linear(_ u: UInt8) -> Int16 {
        let x = Int(~u) & 0xFF
        let sign = x & 0x80
        let exponent = (x >> 4) & 0x07
        let mantissa = x & 0x0F
        var sample = ((mantissa << 3) + 0x84) << exponent
        sample -= 0x84
        return Int16(sign != 0 ? -sample : sample)
    }

    static func alaw2linear(_ a: UInt8) -> Int16 {
        let x = Int(a ^ 0x55) & 0xFF
        let sign = x & 0x80
        let exponent = (x >> 4) & 0x07
        let mantissa = x & 0x0F
        var sample: Int
        if exponent == 0 {
            sample = (mantissa << 4) + 8
        } else {
            sample = ((mantissa << 4) + 0x108) << (exponent - 1)
        }
        return Int16(sign != 0 ? sample : -sample)
    }

    /// G.711 → 16bit PCM（小端，直接给 AVAudioPCMBuffer 用）
    static func decode(_ bytes: [UInt8], aLaw: Bool) -> [Int16] {
        var out = [Int16](repeating: 0, count: bytes.count)
        for i in 0..<bytes.count {
            out[i] = aLaw ? alaw2linear(bytes[i]) : ulaw2linear(bytes[i])
        }
        return out
    }
}
