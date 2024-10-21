import SwiftUI
import UIKit
import AVFoundation
import MetalKit

let flatSpaceText = """
    Selected spacetime: flat space \n
"""

let schwarzschildText = """
    Selected spacetime: Schwarzschild black hole \n
"""

let kerrText = """
    Selected spacetime: Kerr black hole \n
"""

let fullFovText = """
    Selected field-of-view mode: stretched
"""

let actualFovText = """
    Selected field-of-view mode: realistic
"""

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
        
        @objc func handleTapGesture(_ sender: UITapGestureRecognizer) {
            parent.counter += 1
            print("Coordinator: view was tapped! Counter: \(parent.counter)")
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
                handleFullFovSelection()
            case 1:
                handleRealisticFovSelection()
            default:
                break
            }
        }

        func handleFlatSpaceSelection() {
            print("hello from flat space selection")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.spaceTimeMode = 0
        }
        func handleSchwarzschildSelection() {
            print("hello from schwarzschild selection")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.spaceTimeMode = 1
        }
        func handleKerrSelection() { 
            print("hello from kerr selection")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.spaceTimeMode = 2
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
        
        /*
        viewController.helloWorldButton.addTarget(context.coordinator,
                                                  action: #selector(Coordinator.handleHelloWorldButton(_:)),
                                                  for: .touchUpInside)
        */
        
        viewController.spacetimeSegmentedControl.addTarget(context.coordinator,
                                                           action: #selector(context.coordinator.spacetimeModeChanged(_:)),
                                                           for: .valueChanged)
        viewController.fovSegmentedControl.addTarget(context.coordinator,
                                                     action: #selector(context.coordinator.fovModeChanged(_:)),
                                                     for: .valueChanged)

        context.coordinator.multiCamViewController = viewController
        return viewController
    }
    
    /*
    func makeUIViewController(context: Context) -> UIViewController {
        // let viewController = UIViewController()
        let viewController = MultiCamViewController()
        
        // Add the main, metal kit view that will display the filtered image
        let mtkView = context.coordinator.mtkView
        mtkView.frame = CGRect(x: 0,
                               y: 0,
                               width:   viewController.view.bounds.width,
                               height:  viewController.view.bounds.height)
        viewController.mtkView = mtkView

        // Next add a menu overlay that is initially hidden
        let overlayMenuView = UIView(frame: viewController.view.bounds)
        overlayMenuView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayMenuView.isHidden = true
        viewController.overlayMenuView = overlayMenuView
        
        let label = UILabel(frame: CGRect(x: 10, y: 300, width: overlayMenuView.bounds.width - 40, height: 50))
        label.numberOfLines = 0
        label.text = flatSpaceText + actualFovText
        label.textColor = .white
        label.textAlignment = .left
        overlayMenuView.addSubview(label)
        

        let multiCamCapture = context.coordinator.multiCamCapture
        multiCamCapture.delegate = context.coordinator
        multiCamCapture.startRunning()
        
        // Add gesture support
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
        viewController.view.addGestureRecognizer(tapGesture)
        
        let button1 = createButton(withTitle: "η", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton1(_:)))
        let button2 = createButton(withTitle: "S", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton2(_:)))
        let button3 = createButton(withTitle: "K", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton3(_:)))
        let button4 = createButton(withTitle: "P", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton4(_:)))
        let button5 = createButton(withTitle: "F", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton5(_:)))
        
        let menuButton = createButton(withTitle: "M", target: context.coordinator,
                                   action: #selector(context.coordinator.handleMenuButton(_:)))

        // Order determines layering
        viewController.view.addSubview(mtkView)
        viewController.view.addSubview(button1)
        viewController.view.addSubview(button2)
        viewController.view.addSubview(button3)
        viewController.view.addSubview(button4)
        viewController.view.addSubview(button5)
        viewController.view.addSubview(overlayMenuView)
        viewController.view.addSubview(menuButton)

        button1.translatesAutoresizingMaskIntoConstraints = false
        button2.translatesAutoresizingMaskIntoConstraints = false
        button3.translatesAutoresizingMaskIntoConstraints = false
        button4.translatesAutoresizingMaskIntoConstraints = false
        button5.translatesAutoresizingMaskIntoConstraints = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        // Define the layout constraints
        NSLayoutConstraint.activate([
            button1.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button1.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: -160),
            button1.widthAnchor.constraint(equalToConstant: 50),
            button1.heightAnchor.constraint(equalToConstant: 50),

            button2.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button2.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: -90),
            button2.widthAnchor.constraint(equalToConstant: 50),
            button2.heightAnchor.constraint(equalToConstant: 50),

            button3.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button3.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: -20),
            button3.widthAnchor.constraint(equalToConstant: 50),
            button3.heightAnchor.constraint(equalToConstant: 50),
            
            button4.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button4.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: 90),
            button4.widthAnchor.constraint(equalToConstant: 50),
            button4.heightAnchor.constraint(equalToConstant: 50),
            
            button5.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button5.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: 160),
            button5.widthAnchor.constraint(equalToConstant: 50),
            button5.heightAnchor.constraint(equalToConstant: 50),
            
            menuButton.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor, constant: 50),
            menuButton.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 50),
            menuButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        context.coordinator.multiCamViewController = viewController
        return viewController
    }
    */

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
    
    private func createButton(withTitle title: String, target: Any?, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(target, action: action, for: .touchUpInside)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.clipsToBounds = true
        button.layer.cornerRadius = 25
        return button
    }
}

class MultiCamViewController: UIViewController {
    var mtkView: MTKView!
    
    @IBOutlet weak var spacetimeSegmentedControl: UISegmentedControl!
    @IBOutlet weak var fovSegmentedControl: UISegmentedControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}
