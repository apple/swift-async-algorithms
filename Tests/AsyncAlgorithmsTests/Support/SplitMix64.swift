// Taken from: https://github.com/swiftlang/swift/blob/main/benchmark/utils/TestsUtils.swift#L257-L271
public struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64
  
  public init(seed: UInt64) {
    self.state = seed
  }
  
  public mutating func next() -> UInt64 {
    self.state &+= 0x9e37_79b9_7f4a_7c15
    var z: UInt64 = self.state
    z = (z ^ (z &>> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z &>> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z &>> 31)
  }
}
