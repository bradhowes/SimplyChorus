// Copyright © 2021 Brad Howes. All rights reserved.

#pragma once

#import <algorithm>
#import <numeric>
#import <string>
#import <AVFoundation/AVFoundation.h>

#import "DSPHeaders/BoolParameter.hpp"
#import "DSPHeaders/BusBuffers.hpp"
#import "DSPHeaders/DelayBuffer.hpp"
#import "DSPHeaders/EventProcessor.hpp"
#import "DSPHeaders/MillisecondsParameter.hpp"
#import "DSPHeaders/LFO.hpp"
#import "DSPHeaders/PercentageParameter.hpp"

/**
 The audio processing kernel that generates a "flange" effect by combining an audio signal with a slightly delayed copy
 of itself. The delay value oscillates at a defined frequency which causes the delayed audio to vary in pitch due to it
 being sped up or slowed down.
 */
class Kernel : public DSPHeaders::EventProcessor<Kernel> {
public:
  using super = DSPHeaders::EventProcessor<Kernel>;
  friend super;

  /**
   Construct new kernel

   @param name the name to use for logging purposes.
   */
  Kernel(std::string name) noexcept : super(name) {}

  /**
   Update kernel and buffers to support the given format and channel count

   @param format the audio format to render
   @param maxFramesToRender the maximum number of samples we will be asked to render in one go
   @param maxDelayMilliseconds the max number of milliseconds of audio samples to keep in delay buffer
   */
  void setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender,
                          double maxDelayMilliseconds) noexcept {
    super::setRenderingFormat(busCount, format, maxFramesToRender);
    initialize(format.channelCount, format.sampleRate, maxDelayMilliseconds);
  }

  /**
   Process an AU parameter value change by updating the kernel.

   @param address the address of the parameter that changed
   @param value the new value for the parameter
   */
  void setParameterValue(AUParameterAddress address, AUValue value) noexcept;

  /**
   Obtain from the kernel the current value of an AU parameter.

   @param address the address of the parameter to return
   @returns current parameter value
   */
  AUValue getParameterValue(AUParameterAddress address) const noexcept;

private:
  inline static constexpr size_t TapCount = 5;
  using DelayLine = DSPHeaders::DelayBuffer<AUValue>;
  using DelayIndices = std::array<AUValue, TapCount>;
  using LFO = DSPHeaders::LFO<AUValue>;

  void initialize(int channelCount, double sampleRate, double maxDelayMilliseconds) noexcept {
    samplesPerMillisecond_ = sampleRate / 1000.0;

    lfos_.clear();
    auto rate{rate_.get()};
    for (size_t index = 0; index < TapCount; ++index) {
      lfos_.emplace_back(sampleRate, rate * (index * 0.1), LFOWaveform::sinusoid);
    }

    // Size of delay buffer needs to be twice the maxDelay value since at max delay and max depth settings, the bipolar
    // indices into the delay buffer will go from delay * -1 * depth to delay * 1 * depth (approximately).
    auto size = maxDelayMilliseconds * samplesPerMillisecond_ * 2.0 + 1;
    os_log_with_type(log_, OS_LOG_TYPE_INFO, "delayLine size: %f", size);
    delayLines_.clear();
    for (auto index = 0; index < channelCount; ++index) {
      delayLines_.emplace_back(size, DelayLine::Interpolator::cubic4thOrder);
    }
  }

  void setRate(AUValue rate, AUAudioFrameCount rampingDuration) {
    rate_.set(rate, rampingDuration);
    for (auto& lfo : lfos_) lfo.setFrequency(rate, rampingDuration);
  }

  void setRampedParameterValue(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) noexcept;

  void setParameterFromEvent(const AUParameterEvent& event) noexcept {
    if (event.rampDurationSampleFrames == 0) {
      setParameterValue(event.parameterAddress, event.value);
    } else {
      setRampedParameterValue(event.parameterAddress, event.value, event.rampDurationSampleFrames);
    }
  }

  void doRendering(NSInteger outputBusNumber, DSPHeaders::BusBuffers ins, DSPHeaders::BusBuffers outs,
                   AUAudioFrameCount frameCount) noexcept {

    // Advance by frames in outer loop so we can ramp values when they change without having to save/restore state.
    for (int frame = 0; frame < frameCount; ++frame) {

      auto delay = delay_.frameValue();
      auto depth = depth_.frameValue();

      constexpr AUValue minDelay = 1.0E-3;
      if (delay - depth < minDelay) {
        depth = delay - minDelay;
      }

      auto wetMix = wetMix_.frameValue();
      auto dryMix = dryMix_.frameValue();

      auto odd90 = odd90_.get();

      if (delay == 0.0 || depth == 0.0) {
        for (int channel = 0; channel < ins.size(); ++channel) {
          *outs[channel]++ = *ins[channel]++;
        }
      } else {
        for (size_t index = 0; index < TapCount; ++index) {
          evenDelays_[index] = lfos_[index].value() * depth + delay;
          if (odd90) {
            oddDelays_[index] = lfos_[index].quadPhaseValue() * depth + delay;
          }
          lfos_[index].increment();
        }

        for (int channel = 0; channel < ins.size(); ++channel) {
          auto inputSample = *ins[channel]++;
          auto delayedSample = getDelayedSample(delayLines_[channel], ((channel & 1) && odd90) ? oddDelays_ : evenDelays_);
          delayLines_[channel].write(inputSample);
          *outs[channel]++ = wetMix * delayedSample + dryMix * inputSample;
        }
      }
    }
  }

  void doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept {}

  AUValue getDelayedSample(const DelayLine& delayLine, const DelayIndices& indices) const noexcept {
    return std::accumulate(indices.begin(), indices.end(), 0.0,
                           [&](AUValue left, AUValue right) { return left + delayLine.read(right); }) / TapCount;
  }

  DSPHeaders::Parameters::RampingParameter<AUValue> rate_;
  DSPHeaders::Parameters::MillisecondsParameter<AUValue> depth_;
  DSPHeaders::Parameters::MillisecondsParameter<AUValue> delay_;
  DSPHeaders::Parameters::PercentageParameter<AUValue> dryMix_;
  DSPHeaders::Parameters::PercentageParameter<AUValue> wetMix_;
  DSPHeaders::Parameters::BoolParameter odd90_;

  double samplesPerMillisecond_;

  std::vector<DelayLine> delayLines_;
  std::vector<DSPHeaders::LFO<AUValue>> lfos_;
  DelayIndices evenDelays_;
  DelayIndices oddDelays_;
};
