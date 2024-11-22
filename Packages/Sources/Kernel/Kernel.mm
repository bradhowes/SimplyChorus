#import "C++/Kernel.hpp"

// This must be done in a source file -- include files cannot see the Swift bridging file which contains the definition
// of ParameterAddress.

@import ParameterAddress;

bool Kernel::doSetImmediateParameterValue(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) noexcept {
  switch (address) {
    case ParameterAddressRate: setRateImmediate(value, duration); return true;
    case ParameterAddressDepth: depth_.setImmediate(value, duration); return true;
    case ParameterAddressDelay: delay_.setImmediate(value, duration); return true;
    case ParameterAddressDry: dryMix_.setImmediate(value, duration); return true;
    case ParameterAddressWet: wetMix_.setImmediate(value, duration); return true;
    case ParameterAddressOdd90: odd90_.setImmediate(value, duration); return true;
  }
  return false;
}

bool Kernel::doSetPendingParameterValue(AUParameterAddress address, AUValue value) noexcept {
  switch (address) {
    case ParameterAddressRate: setRatePending(value); return true;
    case ParameterAddressDepth: depth_.setPending(value); return true;
    case ParameterAddressDelay: delay_.setPending(value); return true;
    case ParameterAddressDry: dryMix_.setPending(value); return true;
    case ParameterAddressWet: wetMix_.setPending(value); return true;
    case ParameterAddressOdd90: odd90_.setPending(value); return true;
  }
  return false;
}

AUValue Kernel::doGetImmediateParameterValue(AUParameterAddress address) const noexcept {
  switch (address) {
    case ParameterAddressRate: return rate_.getImmediate();
    case ParameterAddressDepth: return depth_.getImmediate();
    case ParameterAddressDelay: return delay_.getImmediate();
    case ParameterAddressDry: return dryMix_.getImmediate();
    case ParameterAddressWet: return wetMix_.getImmediate();
    case ParameterAddressOdd90: return odd90_.getImmediate();
  }
  return 0.0;
}

AUValue Kernel::doGetPendingParameterValue(AUParameterAddress address) const noexcept {
  switch (address) {
    case ParameterAddressRate: return rate_.getPending();
    case ParameterAddressDepth: return depth_.getPending();
    case ParameterAddressDelay: return delay_.getPending();
    case ParameterAddressDry: return dryMix_.getPending();
    case ParameterAddressWet: return wetMix_.getPending();
    case ParameterAddressOdd90: return odd90_.getPending();
  }
  return 0.0;
}
