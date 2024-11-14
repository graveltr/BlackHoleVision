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
        
        let spinValues: [Float] = [0.5, 0.9, 0.99, 0.999]
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
        
        @objc func handleControlsButton(_ sender: UIButton) {
            multiCamViewController!.fovSegmentedControl.isHidden = !(multiCamViewController!.fovSegmentedControl.isHidden)
            multiCamViewController!.spacetimeSegmentedControl.isHidden = !(multiCamViewController!.spacetimeSegmentedControl.isHidden)
        }
        
        @objc func handleCameraFlipButton(_ sender: UIButton) {
            mixer.isBlackHoleInFront = (mixer.isBlackHoleInFront == 1) ? 0 : 1
        }

        @objc func spinStepperValueChanged(_ sender: UIStepper) { 
            multiCamViewController!.spinReadoutLabel.text = "a: \(getCurrSpinValue())"
            mixer.filterParameters.a = getCurrSpinValue()
            mixer.needsNewLutTexture = true
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
            
            multiCamViewController?.fovSegmentedControl.selectedSegmentIndex = 0
            multiCamViewController?.fovSegmentedControl.isEnabled = false
            mixer.filterParameters.sourceMode = 1

            mixer.filterParameters.spaceTimeMode = 0
            mixer.needsNewLutTexture = true
        }
        func handleSchwarzschildSelection() {
            multiCamViewController?.spinReadoutLabel.isHidden = true
            multiCamViewController?.spinStepper.isHidden = true
            
            mixer.filterParameters.spaceTimeMode = 1
            
            multiCamViewController?.fovSegmentedControl.isEnabled = true

            mixer.needsNewLutTexture = true
        }
        func handleKerrSelection() { 
            multiCamViewController?.spinReadoutLabel.text = "a: \(getCurrSpinValue())"
            multiCamViewController?.spinReadoutLabel.isHidden = false
            
            multiCamViewController?.spinStepper.isHidden = false
            
            mixer.filterParameters.spaceTimeMode = 2
            mixer.filterParameters.a = getCurrSpinValue()
            
            multiCamViewController?.fovSegmentedControl.selectedSegmentIndex = 1
            multiCamViewController?.fovSegmentedControl.isEnabled = false
            mixer.filterParameters.sourceMode = 0

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
        let aRatio = 1920.0 / 1080.0
        mtkView.frame = CGRect(x: 0,
                               y: 0,
                               width:   viewController.view.bounds.width,
                               height:  viewController.view.bounds.height)
        
        // TODO: make sure the centering is correct
        /*
        mtkView.frame = CGRect(x: 0,
                               y: 0,
                               width:   viewController.view.bounds.height / aRatio,
                               height:  viewController.view.bounds.height)
        */
        
        viewController.mtkView = mtkView
        viewController.view.addSubview(mtkView)
        viewController.view.sendSubviewToBack(mtkView)
        
        viewController.spinReadoutLabel.isHidden = true

        viewController.controlsButton.addTarget(context.coordinator,
                                                action: #selector(context.coordinator.handleControlsButton(_:)),
                                                for: .touchUpInside)
        
        viewController.cameraFlipButton.addTarget(context.coordinator,
                                                  action: #selector(context.coordinator.handleCameraFlipButton(_:)),
                                                  for: .touchUpInside)
        
        viewController.spinStepper.tintColor = UIColor.red
        viewController.spinStepper.addTarget(context.coordinator,
                                             action: #selector(context.coordinator.spinStepperValueChanged(_:)),
                                             for: .valueChanged)
        
        viewController.spacetimeSegmentedControl.addTarget(context.coordinator,
                                                           action: #selector(context.coordinator.spacetimeModeChanged(_:)),
                                                           for: .valueChanged)
        viewController.fovSegmentedControl.addTarget(context.coordinator,
                                                     action: #selector(context.coordinator.fovModeChanged(_:)),
                                                     for: .valueChanged)

        viewController.spinStepper.isHidden = true
        viewController.fovSegmentedControl.isEnabled = false

        context.coordinator.multiCamViewController = viewController
        context.coordinator.mixer.filterParameters.a = context.coordinator.getCurrSpinValue()
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}

class MultiCamViewController: UIViewController {
    var mtkView: MTKView!
    
    @IBOutlet weak var spinReadoutLabel: UILabel!
    
    @IBOutlet weak var controlsButton: UIButton!
    @IBOutlet weak var cameraFlipButton: UIButton!

    @IBOutlet weak var spacetimeSegmentedControl: UISegmentedControl!
    @IBOutlet weak var fovSegmentedControl: UISegmentedControl!
    
    @IBOutlet weak var spinStepper: UIStepper!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
