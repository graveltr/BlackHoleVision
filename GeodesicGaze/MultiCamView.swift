import SwiftUI
import UIKit
import AVFoundation
import MetalKit
import AudioToolbox

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
            if mixer.filterParameters.spaceTimeMode == 2 {
                multiCamViewController!.spinStepper.isHidden = !(multiCamViewController!.spinStepper.isHidden)
                multiCamViewController!.spinReadoutLabel.isHidden = !(multiCamViewController!.spinReadoutLabel.isHidden)
            }
        }
        
        @objc func handleCameraFlipButton(_ sender: UIButton) {
            mixer.isBlackHoleInFront = (mixer.isBlackHoleInFront == 1) ? 0 : 1
        }
        
        @objc func handlePipButton(_ sender: UIButton) {
            mixer.isPipEnabled = (mixer.isPipEnabled == 1) ? 0 : 1
        }
        
        @objc func handleScreenshotButton(_ sender: UIButton) {
            mixer.shouldTakeScreenshot = true
            
            guard let flashView = multiCamViewController?.flashView else {
                print("no flashview")
                return
            }
            
            UIView.animate(withDuration: 0.2, animations: {
                flashView.alpha = 1
            })
            UIView.animate(withDuration: 0.2, animations: {
                flashView.alpha = 0
            })
            AudioServicesPlaySystemSound(1108)
        }
        
        @objc func handleDescriptionButton(_ sender: UIButton) {
            guard let descriptionView = multiCamViewController?.descriptionView else {
                print("no description view")
                return
            }
            guard let infoTextView = multiCamViewController?.infoTextView else {
                print("no info text view")
                return
            }
            guard let activateButton = multiCamViewController?.activateButton else {
                print("no activate button")
                return
            }
            
            activateButton.isEnabled = true

            multiCamViewController?.view.bringSubviewToFront(descriptionView)
            multiCamViewController?.view.bringSubviewToFront(infoTextView)
            multiCamViewController?.view.bringSubviewToFront(activateButton)

            UIView.animate(withDuration: 0.2, animations: {
                descriptionView.alpha = 1
                infoTextView.alpha = 1
                activateButton.alpha = 1
            })
        }
        
        @objc func handleActivateButton(_ sender: UIButton) {
            guard let descriptionView = multiCamViewController?.descriptionView else {
                print("no description view")
                return
            }
            guard let infoTextView = multiCamViewController?.infoTextView else {
                print("no info text view")
                return
            }
            guard let activateButton = multiCamViewController?.activateButton else {
                print("no activate button")
                return
            }
            
            activateButton.isEnabled = false

            multiCamViewController?.view.sendSubviewToBack(descriptionView)
            multiCamViewController?.view.sendSubviewToBack(infoTextView)
            multiCamViewController?.view.sendSubviewToBack(activateButton)

            UIView.animate(withDuration: 0.2, animations: {
                descriptionView.alpha = 0
                infoTextView.alpha = 0
                activateButton.alpha = 0
            })
        }
        
        @objc func handleToggleButton(_ sender: UIButton) {
            let currSchwarzschildMode = mixer.filterParameters.schwarzschildMode
            if (currSchwarzschildMode == 0) {
                mixer.filterParameters.schwarzschildMode = 1
                mixer.filterParameters.sourceMode = 1
                multiCamViewController?.schwarzschildModeLabel.text = "Old Mode"
            } else {
                mixer.filterParameters.schwarzschildMode = 0
                mixer.filterParameters.sourceMode = 0
                multiCamViewController?.schwarzschildModeLabel.text = "New Mode"
            }
            mixer.needsNewLutTexture = true
        }

        @objc func spinStepperValueChanged(_ sender: UIStepper) { 
            multiCamViewController!.spinReadoutLabel.text = "Black hole spin: \(getCurrSpinValue() * 100)%"
            mixer.filterParameters.a = getCurrSpinValue()
            mixer.needsNewLutTexture = true
        }
        
        @objc func distanceSliderValueChanged(_ sender: UISlider) {
            let dist: Float = sender.value
            mixer.filterParameters.d = dist
            mixer.needsNewLutTexture = true
            
            multiCamViewController?.distanceReadoutLabel.text = "Distance from black hole: \(String(format: "%.0f", dist)) M"
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
            multiCamViewController?.distanceReadoutLabel.isHidden = true
            multiCamViewController?.distanceSlider.isHidden = true

            multiCamViewController?.fovSegmentedControl.selectedSegmentIndex = 0
            multiCamViewController?.fovSegmentedControl.isEnabled = false
            mixer.filterParameters.sourceMode = 1

            mixer.filterParameters.spaceTimeMode = 0
            mixer.needsNewLutTexture = true
        }
        func handleSchwarzschildSelection() {
            multiCamViewController?.spinReadoutLabel.isHidden = true
            multiCamViewController?.spinStepper.isHidden = true
            
            multiCamViewController?.distanceReadoutLabel.text = "Distance from black hole: \(String(format: "%.0f", getCurrDistanceValue())) M"
            multiCamViewController?.distanceReadoutLabel.isHidden = false
            multiCamViewController?.distanceSlider.isHidden = false

            mixer.filterParameters.spaceTimeMode = 1
            mixer.filterParameters.d = getCurrDistanceValue()
            
            multiCamViewController?.fovSegmentedControl.isEnabled = false

            multiCamViewController?.schwarzschildModeLabel.text = "New Mode"
            mixer.filterParameters.schwarzschildMode = 0
            mixer.filterParameters.sourceMode = 0
            mixer.needsNewLutTexture = true
        }
        func handleKerrSelection() { 
            multiCamViewController?.distanceReadoutLabel.isHidden = true
            multiCamViewController?.distanceSlider.isHidden = true
            
            multiCamViewController?.spinReadoutLabel.text = "Black hole spin: \(getCurrSpinValue() * 100)%"
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
        
        func getCurrDistanceValue() -> Float {
            return multiCamViewController!.distanceSlider.value
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
        
        
        var width: Double
        let L = viewController.view.bounds.width
        if L < (viewController.view.bounds.height / aRatio) {
            width = viewController.view.bounds.height / aRatio
        } else {
            width = viewController.view.bounds.width
        }

        let xHat = (L / 2.0) - (width / 2.0)
        let xHatOverWidth = xHat / width;
        mtkView.frame = CGRect(x: xHat,
                               y: 0,
                               width: width,
                               height:  viewController.view.bounds.height)
        context.coordinator.mixer.vcWidthToViewWidth = Float(L) / Float(width)
        context.coordinator.mixer.vcEdgeInViewTextureCoords = abs(Float(xHatOverWidth))

        viewController.mtkView = mtkView
        viewController.view.addSubview(mtkView)
        viewController.view.sendSubviewToBack(mtkView)
        
        viewController.spinReadoutLabel.isHidden = true

        viewController.controlsButton.addTarget(context.coordinator,
                                                action: #selector(context.coordinator.handleControlsButton(_:)),
                                                for: .touchUpInside)
        
        viewController.pipButton.addTarget(context.coordinator,
                                           action: #selector(context.coordinator.handlePipButton(_:)),
                                           for: .touchUpInside)
        
        viewController.screenshotButton.addTarget(context.coordinator,
                                                  action: #selector(context.coordinator.handleScreenshotButton(_:)),
                                                  for: .touchUpInside)
        
        viewController.descriptionButton.addTarget(context.coordinator,
                                                  action: #selector(context.coordinator.handleDescriptionButton(_:)),
                                                  for: .touchUpInside)
        
        viewController.activateButton.addTarget(context.coordinator,
                                                  action: #selector(context.coordinator.handleActivateButton(_:)),
                                                  for: .touchUpInside)

        viewController.cameraFlipButton.addTarget(context.coordinator,
                                                  action: #selector(context.coordinator.handleCameraFlipButton(_:)),
                                                  for: .touchUpInside)
        viewController.toggleButton.addTarget(context.coordinator, action: #selector(context.coordinator.handleToggleButton(_:)), for: .touchUpInside)
        
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

        viewController.distanceSlider.addTarget(context.coordinator,
                                                action: #selector(context.coordinator.distanceSliderValueChanged(_:)),
                                                for: .valueChanged)
        
        viewController.spinStepper.isHidden = true
        viewController.fovSegmentedControl.isEnabled = false
        viewController.distanceSlider.isHidden = true
        viewController.distanceReadoutLabel.isHidden = true
        
        context.coordinator.multiCamViewController = viewController
        context.coordinator.mixer.filterParameters.a = context.coordinator.getCurrSpinValue()
        
        let flashView = UIView(frame: CGRect(x: 0, y: 0,
                                             width: viewController.view.bounds.width,
                                             height: viewController.view.bounds.height))
        flashView.backgroundColor = .white
        flashView.alpha = 0
        viewController.flashView = flashView
        viewController.view.addSubview(flashView)
        viewController.view.bringSubviewToFront(flashView)
        
        let descriptionView = UIView(frame: CGRect(x: 0, y: 0,
                                                   width: viewController.view.bounds.width,
                                                   height: viewController.view.bounds.height))
        descriptionView.backgroundColor = .black
        descriptionView.alpha = 0
        viewController.descriptionView = descriptionView
        viewController.view.addSubview(descriptionView)
        viewController.view.sendSubviewToBack(descriptionView)
        
        viewController.infoTextView.alpha = 0
        viewController.activateButton.alpha = 0
        viewController.activateButton.isEnabled = false

        viewController.spacetimeSegmentedControl.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10)], for: .normal)
        viewController.fovSegmentedControl.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10)], for: .normal)
        viewController.distanceReadoutLabel.font = UIFont.systemFont(ofSize: 12)

        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}

class MultiCamViewController: UIViewController {
    var mtkView: MTKView!
    var flashView: UIView!
    var descriptionView: UIView!
    
    @IBOutlet weak var infoTextView: UITextView!

    @IBOutlet weak var spinReadoutLabel: UILabel!
    @IBOutlet weak var distanceReadoutLabel: UILabel!
    @IBOutlet weak var schwarzschildModeLabel: UILabel!

    @IBOutlet weak var controlsButton: UIButton!
    @IBOutlet weak var pipButton: UIButton!
    @IBOutlet weak var cameraFlipButton: UIButton!
    @IBOutlet weak var screenshotButton: UIButton!
    @IBOutlet weak var descriptionButton: UIButton!
    @IBOutlet weak var activateButton: UIButton!
    @IBOutlet weak var toggleButton: UIButton!

    @IBOutlet weak var spacetimeSegmentedControl: UISegmentedControl!
    @IBOutlet weak var fovSegmentedControl: UISegmentedControl!
    
    @IBOutlet weak var spinStepper: UIStepper!
    
    @IBOutlet weak var distanceSlider: UISlider!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
