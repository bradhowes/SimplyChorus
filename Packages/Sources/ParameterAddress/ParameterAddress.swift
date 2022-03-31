import AudioUnit.AUParameters
import AUv3Support

/**
 These are the unique addresses for the runtime parameters used by the audio unit.
 NOTE: the raw values of this enum are used to index into an array of AUParameter values, so be sure to start at 0 and
 have no gaps.
 */
@objc public enum ParameterAddress: UInt64, CaseIterable {
  case rate = 0
  case depth
  case delay
  case dry
  case wet
  case odd90
};

public extension ParameterAddress {

  /// Obtain a ParameterDefinition for a parameter address enum.
  var parameterDefinition: ParameterDefinition {
    let maxDelay: AUValue = 50.0
    switch self {
    case .rate: return .defFloat("rate", localized: "Rate", address: ParameterAddress.rate,
                                 range: 0.01...20.0, unit: .hertz)
    case .delay: return .defFloat("delay", localized: "Delay", address: ParameterAddress.delay,
                                  range: 0.0...maxDelay, unit: .milliseconds)
    case .depth: return .defPercent("depth", localized: "Depth", address: ParameterAddress.depth)
    case .dry: return .defPercent("dry", localized: "Dry", address: ParameterAddress.dry)
    case .wet: return .defPercent("wet", localized: "Wet", address: ParameterAddress.wet)
    case .odd90: return .defBool("odd90", localized: "Odd 90°", address: ParameterAddress.odd90)
    }
  }
}

extension AUParameter {
  public var parameterAddress: ParameterAddress? { .init(rawValue: self.address) }
}

/// Allow enum values to serve as AUParameterAddress values.
extension ParameterAddress: ParameterAddressProvider {
  public var parameterAddress: AUParameterAddress { UInt64(self.rawValue) }
}

/// Allow UI elements with a `tag` to hold ParameterAddress values
public extension ParameterAddressHolder {
  func setParameterAddress(_ address: ParameterAddress) { parameterAddress = address.rawValue }
  var parameterAddress: ParameterAddress? {
    let raw: AUParameterAddress = parameterAddress
    return ParameterAddress(rawValue: raw)
  }
}

extension ParameterAddress: CustomStringConvertible {
  public var description: String { "<ParameterAddress: '\(parameterDefinition.identifier)' \(rawValue)>" }
}
