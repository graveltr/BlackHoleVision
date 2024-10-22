import SwiftUI
import UIKit
import AVFoundation
import MetalKit

struct MultiCamView: UIViewControllerRepresentable {
    
    @Binding var counter: Int
    @Binding var selectedFilter: Int
    
    
    class Coordinator: NSObject, MultiCamCaptureDelegate, MTKViewDelegate {
        var parent: MultiCamView
        var mixer: BhiMixer
        var mtkView: MTKView
        var multiCamCapture: MultiCamCapture
        var frontCameraPixelBuffer: CVPixelBuffer?
        var backCameraPixelBuffer: CVPixelBuffer?
        
        var multiCamViewController: MultiCamViewController?
        
        let spinValues: [Float] = [0.001, 0.1, 0.5, 0.9, 0.99]
        let distanceValues: [Float] = [10, 100, 1000]

        init(parent: MultiCamView, mtkView: MTKView, mixer: BhiMixer, multiCamCapture: MultiCamCapture) {
            self.parent = parent
            self.mtkView = mtkView
            self.mixer = mixer
            self.multiCamCapture = multiCamCapture
            super.init()
            self.mtkView.delegate = self
        }
        
        func processCameraPixelBuffers(frontCameraPixelBuffer: CVPixelBuffer, backCameraPixelBuffer: CVPixelBuffer) {
            DispatchQueue.main.async {
                self.frontCameraPixelBuffer = frontCameraPixelBuffer
                self.backCameraPixelBuffer = backCameraPixelBuffer
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            mixer.initializeSizeDependentData(width: Int(size.width), height: Int(size.height))
        }
        
        func draw(in view: MTKView) {
            mixer.mix(frontCameraPixelBuffer: frontCameraPixelBuffer,
                      backCameraPixelBuffer: backCameraPixelBuffer,
                      in: view)
        }
        
        @objc func handleAboutButton(_ sender: UIButton) { 
            // TODO: fill this in
        }
        @objc func handleControlsButton(_ sender: UIButton) {
            let currIsHidden = multiCamViewController!.controlsSubView.isHidden
            multiCamViewController!.controlsSubView.isHidden = !currIsHidden
        }

        @objc func spinStepperValueChanged(_ sender: UIStepper) { 
            multiCamViewController!.spinReadoutLabel.text = String(getCurrSpinValue())
            mixer.needsNewLutTexture = true
            mixer.filterParameters.a = getCurrSpinValue()
        }
        @objc func distanceStepperValueChanged(_ sender: UIStepper) {
            let idx = Int(sender.value)
            let selectedValue = distanceValues[idx]
            
            print("idx: \(idx), value: \(selectedValue)")

            mixer.needsNewLutTexture = true
            mixer.filterParameters.d = selectedValue
        }

        @objc func spacetimeModeChanged(_ sender: UISegmentedControl) {
            switch sender.selectedSegmentIndex {
            case 0:
                handleFlatSpaceSelection()
            case 1:
                handleSchwarzschildSelection()
            case 2:
                handleKerrSelection()
            default:
                break
            }
        }
        
        @objc func fovModeChanged(_ sender: UISegmentedControl) {
            switch sender.selectedSegmentIndex {
            case 0:
                handleRealisticFovSelection()
            case 1:
                handleFullFovSelection()
            default:
                break
            }
        }

        func handleFlatSpaceSelection() {
            multiCamViewController?.spinReadoutLabel.isHidden = true
            
            multiCamViewController?.spinStepper.isHidden = true
            multiCamViewController?.spinStepperLabel.isHidden = true
            
            multiCamViewController?.distanceStepper.isHidden = true
            multiCamViewController?.distanceStepperLabel.isHidden = true
            
            mixer.filterParameters.spaceTimeMode = 0
            mixer.needsNewLutTexture = true
        }
        func handleSchwarzschildSelection() {
            multiCamViewController?.spinReadoutLabel.isHidden = true
            
            multiCamViewController?.spinStepper.isHidden = true
            multiCamViewController?.spinStepperLabel.isHidden = true
            
            multiCamViewController?.distanceStepper.isHidden = false
            multiCamViewController?.distanceStepperLabel.isHidden = false
            
            mixer.filterParameters.spaceTimeMode = 1
            
            mixer.needsNewLutTexture = true
        }
        func handleKerrSelection() { 
            multiCamViewController?.spinReadoutLabel.text = String(getCurrSpinValue())
            multiCamViewController?.spinReadoutLabel.isHidden = false

            multiCamViewController?.spinStepper.isHidden = false
            multiCamViewController?.spinStepperLabel.isHidden = false
            
            multiCamViewController?.distanceStepper.isHidden = false
            multiCamViewController?.distanceStepperLabel.isHidden = false
            
            mixer.filterParameters.spaceTimeMode = 2
            mixer.filterParameters.a = getCurrSpinValue()
            
            mixer.needsNewLutTexture = true
        }
        
        func handleFullFovSelection() {
            print("hello from full fov")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.sourceMode = 0
        }
        func handleRealisticFovSelection() { 
            print("hello from realistic fov")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.sourceMode = 1
        }
        
        func getCurrSpinValue() -> Float {
            let currSpinIdx = Int(multiCamViewController!.spinStepper.value)
            return spinValues[currSpinIdx]
        }
    }

    func makeCoordinator() -> Coordinator {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        let mixer = BhiMixer(device: mtkView.device!)
        let multiCamCapture = MultiCamCapture()
        
        return Coordinator(parent: self, mtkView: mtkView, mixer: mixer, multiCamCapture: multiCamCapture)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "MultiCamViewController") as! MultiCamViewController
        
        let multiCamCapture = context.coordinator.multiCamCapture
        multiCamCapture.delegate = context.coordinator
        multiCamCapture.startRunning()

        let mtkView = context.coordinator.mtkView
        mtkView.frame = CGRect(x: 0,
                               y: 0,
                               width:   viewController.view.bounds.width,
                               height:  viewController.view.bounds.height)
        viewController.mtkView = mtkView
        viewController.view.addSubview(mtkView)
        viewController.view.sendSubviewToBack(mtkView)
        
        viewController.aboutButton.addTarget(context.coordinator,
                                             action: #selector(context.coordinator.handleAboutButton(_:)),
                                             for: .touchUpInside)
        viewController.controlsButton.addTarget(context.coordinator,
                                                action: #selector(context.coordinator.handleControlsButton(_:)),
                                             for: .touchUpInside)

        viewController.spinStepper.addTarget(context.coordinator,
                                             action: #selector(context.coordinator.spinStepperValueChanged(_:)),
                                             for: .valueChanged)
        viewController.spinStepper.isHidden = true
        viewController.spinStepperLabel.isHidden = true
        
        viewController.spinReadoutLabel.isHidden = true
        
        viewController.distanceStepper.addTarget(context.coordinator,
                                                 action: #selector(context.coordinator.distanceStepperValueChanged(_:)),
                                                 for: .valueChanged)
        viewController.distanceStepper.isHidden = true
        viewController.distanceStepperLabel.isHidden = true

        viewController.spacetimeSegmentedControl.addTarget(context.coordinator,
                                                           action: #selector(context.coordinator.spacetimeModeChanged(_:)),
                                                           for: .valueChanged)
        viewController.fovSegmentedControl.addTarget(context.coordinator,
                                                     action: #selector(context.coordinator.fovModeChanged(_:)),
                                                     for: .valueChanged)

        context.coordinator.multiCamViewController = viewController
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}

class MultiCamViewController: UIViewController {
    var mtkView: MTKView!
    
    @IBOutlet weak var spinReadoutLabel: UILabel!
    
    @IBOutlet weak var controlsSubView: UIView!
    
    @IBOutlet weak var aboutButton: UIButton!
    @IBOutlet weak var controlsButton: UIButton!

    @IBOutlet weak var spacetimeSegmentedControl: UISegmentedControl!
    @IBOutlet weak var fovSegmentedControl: UISegmentedControl!
    
    @IBOutlet weak var spinStepperLabel: UILabel!
    @IBOutlet weak var spinStepper: UIStepper!
    
    @IBOutlet weak var distanceStepperLabel: UILabel!
    @IBOutlet weak var distanceStepper: UIStepper!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
