// Copyright © 2022 Brad Howes. All rights reserved.

import AUv3Support
import CoreAudioKit
import KernelBridge
import Kernel
import Knob_iOS
import ParameterAddress
import Parameters
import os.log

/**
 Controller for the AUv3 filter view. Handles wiring up of the controls with AUParameter settings.
 */
@objc open class ViewController: AUViewController {

  // NOTE: this special form sets the subsystem name and must run before any other logger calls.
  private let log = Shared.logger(Bundle.main.auBaseName + "AU", "ViewController")

  private var viewConfig: AUAudioUnitViewConfiguration!

  @IBOutlet weak var titleLabel: UILabel!
  @IBOutlet weak var controlsView: View!

  @IBOutlet weak var rateControl: Knob!
  @IBOutlet weak var rateValueLabel: Label!
  @IBOutlet weak var rateTapEdit: UIView!

  @IBOutlet weak var altRateControl: Knob!
  @IBOutlet weak var altRateValueLabel: Label!
  @IBOutlet weak var altRateTapEdit: UIView!

  @IBOutlet weak var delayControl: Knob!
  @IBOutlet weak var delayValueLabel: Label!
  @IBOutlet weak var delayTapEdit: UIView!

  @IBOutlet weak var depthControl: Knob!
  @IBOutlet weak var depthValueLabel: Label!
  @IBOutlet weak var depthTapEdit: UIView!

  @IBOutlet weak var dryMixControl: Knob!
  @IBOutlet weak var dryMixValueLabel: Label!
  @IBOutlet weak var dryMixTapEdit: UIView!

  @IBOutlet weak var wetMixControl: Knob!
  @IBOutlet weak var wetMixValueLabel: Label!
  @IBOutlet weak var wetMixTapEdit: UIView!

  @IBOutlet weak var odd90Control: Switch!

  private lazy var controls: [ParameterAddress: [(Knob, Label, UIView)]] = [
    .rate: [(rateControl, rateValueLabel, rateTapEdit),
           (altRateControl, altRateValueLabel, altRateTapEdit)],
    .delay: [(delayControl, delayValueLabel, delayTapEdit)],
    .depth: [(depthControl, depthValueLabel, depthTapEdit)],
    .wet: [(wetMixControl, wetMixValueLabel, wetMixTapEdit)],
    .dry: [(dryMixControl, dryMixValueLabel, dryMixTapEdit)]
  ]

  private lazy var switches: [ParameterAddress: Switch] = [
    .odd90: odd90Control,
  ]

  // Holds all of the other editing views and is used to end editing when tapped.
  @IBOutlet weak var editingContainerView: View!
  // Background that contains the label and value editor field. Always appears just above the keyboard view.
  @IBOutlet weak var editingBackground: UIView!
  // Shows the name of the value being edited
  @IBOutlet weak var editingLabel: Label!
  // Shows the name of the value being edited
  @IBOutlet weak var editingValue: UITextField!
  // The top constraint of the editingView. Set to 0 when loaded, but otherwise not used.
  @IBOutlet weak var editingViewTopConstraint: NSLayoutConstraint!
  // The bottom constraint of the editingBackground that controls the vertical position of the editor
  @IBOutlet weak var editingBackgroundBottomConstraint: NSLayoutConstraint!

  // Mapping of parameter address value to array of controls. Use array since two controls exist in pairs to handle
  // constrained width layouts.
  private var editors = [AUParameterEditor]()
  private var editorMap = [ParameterAddress : [AUParameterEditor]]()

  public var audioUnit: FilterAudioUnit? {
    didSet {
      DispatchQueue.main.async {
        if self.isViewLoaded {
          self.createEditors()
        }
      }
    }
  }
}

public extension ViewController {

  override func viewDidLoad() {
    os_log(.info, log: log, "viewDidLoad BEGIN")
    super.viewDidLoad()

    view.backgroundColor = .black
    if audioUnit != nil {
      createEditors()
    }
  }
}

// MARK: - AudioUnitViewConfigurationManager

extension ViewController: AudioUnitViewConfigurationManager {}

// MARK: - AUAudioUnitFactory

extension ViewController: AUAudioUnitFactory {

  nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
    try DispatchQueue.main.sync {
      let bundle = InternalConstants.bundle
      let parameters = Parameters()
      let kernel = KernelBridge(
        bundle.auBaseName,
        maxDelayMilliseconds: parameters[.delay].maxValue,
        numLFOs: 1
      )

      let audioUnit = try FilterAudioUnitFactory.create(
        componentDescription: componentDescription,
        parameters: parameters,
        kernel: kernel,
        viewConfigurationManager: self
      )

      self.audioUnit = audioUnit

      return audioUnit
    }
  }
}

extension ViewController: AUParameterEditorDelegate {

  public func parameterEditorEditingDone(changed: Bool) {
    if changed {
      audioUnit?.clearCurrentPresetIfFactoryPreset()
    }
  }
}

// MARK: - Private

extension ViewController {

  private func createEditors() {
    os_log(.info, log: log, "createEditors BEGIN")

    guard let audioUnit,
          let parameterTree = audioUnit.parameterTree
    else {
      return
    }

    let knobColor = UIColor.knobProgress

    let valueEditor = ValueEditor(containerView: editingContainerView, backgroundView: editingBackground,
                                  parameterName: editingLabel, parameterValue: editingValue,
                                  containerViewTopConstraint: editingViewTopConstraint,
                                  backgroundViewBottomConstraint: editingBackgroundBottomConstraint,
                                  controlsView: controlsView)

    for (parameterAddress, pairs) in controls {
      var editors = [AUParameterEditor]()
      for (knob, label, tapEdit) in pairs {
        knob.progressColor = knobColor
        knob.indicatorColor = knobColor

        knob.addTarget(self, action: #selector(handleKnobChanged(_:)), for: .valueChanged)
        let editor = FloatParameterEditor(parameter: parameterTree[parameterAddress],
                                          formatting: parameterTree[parameterAddress],
                                          rangedControl: knob, label: label)
        editor.delegate = self

        editors.append(editor)
        self.editors.append(editor)
        editor.setValueEditor(valueEditor: valueEditor, tapToEdit: tapEdit)
      }
      self.editorMap[parameterAddress] = editors
    }

    os_log(.info, log: log, "createEditors - creating bool parameter editors")
    for (parameterAddress, control) in switches {
      os_log(.info, log: log, "createEditors - before BooleanParameterEditor")
      control.addTarget(self, action: #selector(handleSwitchChanged(_:)), for: .valueChanged)
      let editor = BooleanParameterEditor(parameter: parameterTree[parameterAddress], booleanControl: control)
      editors.append(editor)
      editorMap[parameterAddress] = [editor]
    }

    os_log(.info, log: log, "createEditors END")
  }

  @objc public func handleKnobChanged(_ control: Knob) {
    guard let address = control.parameterAddress else { fatalError() }
    handleControlChanged(control, address: address)
  }

  @objc public func handleSwitchChanged(_ control: Switch) {
    guard let address = control.parameterAddress else { fatalError() }
    handleControlChanged(control, address: address)
  }

  private func handleControlChanged(_ control: AUParameterValueProvider, address: ParameterAddress) {
    guard let audioUnit,
          let parameterTree = audioUnit.parameterTree
    else {
      return
    }

    os_log(.debug, log: log, "handleControlChanged BEGIN - %d %f %f", address.rawValue, control.value,
           parameterTree[address].value)

    guard let editors = editorMap[address] else {
      os_log(.debug, log: log, "handleControlChanged END - nil editors")
      return
    }

    if editors.contains(where: { $0.differs }) {
      audioUnit.clearCurrentPresetIfFactoryPreset()
    }

    editors.forEach { $0.controlChanged(source: control) }

    os_log(.debug, log: log, "handleControlChanged END")
  }
}

private enum InternalConstants {
  private class EmptyClass {}
  static let bundle = Bundle(for: InternalConstants.EmptyClass.self)
}

extension Knob: @retroactive AUParameterValueProvider, @retroactive RangedControl {}

extension AUParameterTree {
  fileprivate subscript (_ parameter: ParameterAddress) -> AUParameter {
    guard let parameter = self.parameter(source: parameter) else {
      fatalError("Unexpected parameter address \(parameter)")
    }
    return parameter
  }
}
