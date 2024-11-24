// Copyright © 2021 Brad Howes. All rights reserved.

#pragma once

#import <os/log.h>
#import <algorithm>
#import <string>
#import <tuple>
#import <vector>
#import <AVFoundation/AVFoundation.h>

#import "DSPHeaders/BusBuffers.hpp"
#import "DSPHeaders/DelayBuffer.hpp"
#import "DSPHeaders/EventProcessor.hpp"
#import "DSPHeaders/LFO.hpp"
#import "DSPHeaders/Parameters/Bool.hpp"
#import "DSPHeaders/Parameters/Milliseconds.hpp"
#import "DSPHeaders/Parameters/Percentage.hpp"

@import ParameterAddress;

/**
 The audio processing kernel that generates a "chorus" effect by combining an audio signal with a slightly delayed copy
 of itself. The delay value oscillates at a defined frequency which causes the delayed audio to vary in pitch due to it
 being sped up or slowed down.
 */
class Kernel : public DSPHeaders::EventProcessor<Kernel> {
public:
  using super = DSPHeaders::EventProcessor<Kernel>;
  friend super;

  inline static constexpr size_t MAX_LFOS{50};

  /**
   Construct new kernel

   @param name the name to use for logging purposes.
   */
  Kernel(std::string name, size_t lfoCount = 10) noexcept :
  super(), name_{name}, lfoCount_{lfoCount}, log_{os_log_create(name_.c_str(), "Kernel")}
  {
    os_log_debug(log_, "constructor");
    registerParameters({rate_, depth_, delay_, dryMix_, wetMix_, odd90_});
  }

  /**
   Update kernel and buffers to support the given format and channel count

   @param busCount the number of busses to support
   @param format the audio format to render
   @param maxFramesToRender the maximum number of samples we will be asked to render in one go
   @param maxDelayMilliseconds the max number of milliseconds of audio samples to keep in delay buffer
   */
  void setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender,
                          double maxDelayMilliseconds) noexcept {
    super::setRenderingFormat(busCount, format, maxFramesToRender);
    initialize(format.channelCount, format.sampleRate, maxDelayMilliseconds);
  }

private:
  using DelayLine = DSPHeaders::DelayBuffer<AUValue>;
  using LFO = DSPHeaders::LFO<AUValue>;

  void initialize(int channelCount, double sampleRate, double maxDelayMilliseconds) noexcept {
    maxDelayMilliseconds_ = maxDelayMilliseconds;
    samplesPerMillisecond_ = sampleRate / 1000.0;

    lfos_.clear();
    taps_.clear();

    for (int index = 0; index < lfoCount_; ++index) {
      lfos_.emplace_back(rate_, AUValue(sampleRate));
      lfos_.back().setPhase(index / lfoCount_);
      taps_.emplace_back(0.0, 0.0);
    }

    auto size = maxDelayMilliseconds * samplesPerMillisecond_ * 2 + 1;
    delayLines_.clear();
    for (auto index = 0; index < channelCount; ++index) {
      delayLines_.emplace_back(size, DelayLine::Interpolator::cubic4thOrder);
    }
  }

  AUValue generate(AUValue inputSample, const DelayLine& delayLine, bool isEven) const noexcept {
    AUValue output{0.0};
    for (size_t index = 0; index < lfoCount_; ++index) {
      const auto& tap{taps_[index]};
      output += delayLine.read(isEven ? std::get<0>(tap) : std::get<1>(tap));
    }
    return output / lfoCount_;
  }

  void writeSample(DSPHeaders::BusBuffers ins, DSPHeaders::BusBuffers outs, bool odd90, AUValue wetMix, AUValue dryMix) noexcept {
    for (int channel = 0; channel < ins.size(); ++channel) {
      auto inputSample = *ins[channel]++;
      AUValue outputSample = generate(inputSample, delayLines_[channel], channel & 1);
      delayLines_[channel].write(inputSample);
      *outs[channel]++ = wetMix * outputSample + dryMix * inputSample;
    }
  }

  std::tuple<AUValue, AUValue> calcTap(LFO& lfo, AUValue nominalMilliseconds, AUValue displacementMilliseconds,
                                       bool odd90) noexcept {
    auto evenTap = (nominalMilliseconds + lfo.value() * displacementMilliseconds) * samplesPerMillisecond_;
    auto oddTap = (odd90
                   ? (nominalMilliseconds + lfo.quadPhaseValue() * displacementMilliseconds) * samplesPerMillisecond_
                   : evenTap);
    lfo.increment();
    return {evenTap, oddTap};
  }

  void calcTaps(AUValue nominalMilliseconds, AUValue displacementMilliseconds, bool odd90) noexcept {
    for (size_t index = 0; index < lfoCount_; ++index) {
      taps_[index] = calcTap(lfos_[index], nominalMilliseconds, displacementMilliseconds, odd90);
    }
  }

  AUValue calcDisplacement(AUValue nominal, AUValue displacementFraction) const noexcept {
    return (maxDelayMilliseconds_ - nominal) * displacementFraction;
  }

  void doRendering(NSInteger outputBusNumber, DSPHeaders::BusBuffers ins, DSPHeaders::BusBuffers outs,
                   AUAudioFrameCount frameCount) noexcept {
    auto odd90 = odd90_.frameValue();
    if (frameCount == 1) {
      auto nominal = delay_.frameValue();
      auto displacementFraction = depth_.frameValue();
      calcTaps(nominal, calcDisplacement(nominal, displacementFraction), odd90);
      writeSample(ins, outs, odd90, wetMix_.frameValue(), dryMix_.frameValue());
    } else {
      auto nominal = delay_.frameValue();
      auto displacementFraction = depth_.frameValue();
      auto displacement = calcDisplacement(nominal, displacementFraction);
      auto wetMix = wetMix_.frameValue();
      auto dryMix = dryMix_.frameValue();
      for (; frameCount > 0; --frameCount) {
        calcTaps(nominal, displacement, odd90);
        writeSample(ins, outs, odd90, wetMix, dryMix);
      }
    }
  }

  DSPHeaders::Parameters::Float rate_{ParameterAddressRate};
  DSPHeaders::Parameters::Percentage depth_{ParameterAddressDepth};
  DSPHeaders::Parameters::Milliseconds delay_{ParameterAddressDelay};
  DSPHeaders::Parameters::Percentage dryMix_{ParameterAddressDry};
  DSPHeaders::Parameters::Percentage wetMix_{ParameterAddressWet};
  DSPHeaders::Parameters::Bool odd90_{ParameterAddressOdd90};

  size_t lfoCount_;
  double samplesPerMillisecond_;
  double maxDelayMilliseconds_{0};

  std::vector<DelayLine> delayLines_;
  std::vector<LFO> lfos_{};
  std::vector<std::tuple<AUValue, AUValue>> taps_{};
  std::string name_;
  os_log_t log_;

  friend void testRamping(Kernel& kernel, AUAudioFrameCount duration);
};
