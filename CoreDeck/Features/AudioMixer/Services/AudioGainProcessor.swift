import Foundation

enum AudioGainProcessor {
    static func apply(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        sampleCount: Int,
        gain: Float
    ) {
        let safeGain = min(max(gain, 0), 1)
        for index in 0..<sampleCount {
            output[index] = min(max(input[index] * safeGain, -1), 1)
        }
    }
}
