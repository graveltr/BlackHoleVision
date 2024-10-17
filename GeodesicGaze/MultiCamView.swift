import SwiftUI
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
        
        @objc func handleButton1(_ sender: UIButton) {
            sender.isEnabled = false
            print("Button1: button was tapped!")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.sourceMode = 0
            mixer.filterParameters.spaceTimeMode = 0
            sender.isEnabled = true
        }
        
        @objc func handleButton2(_ sender: UIButton) {
            print("Button2: button was tapped!")
            sender.isEnabled = false
            print("Button1: button was tapped!")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.sourceMode = 1
            mixer.filterParameters.spaceTimeMode = 1
            sender.isEnabled = true
        }
        
        @objc func handleButton3(_ sender: UIButton) {
            print("Button3: button was tapped!")
            sender.isEnabled = false
            print("Button1: button was tapped!")
            mixer.needsNewLutTexture = true
            mixer.filterParameters.sourceMode = 0
            mixer.filterParameters.spaceTimeMode = 1
            sender.isEnabled = true
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
        let viewController = UIViewController()
        
        let mtkView = context.coordinator.mtkView
        mtkView.frame = CGRect(x: 0,
                               y: 0,
                               width:   viewController.view.bounds.width,
                               height:  viewController.view.bounds.height)
        
        viewController.view.addSubview(mtkView)

        let multiCamCapture = context.coordinator.multiCamCapture
        multiCamCapture.delegate = context.coordinator
        multiCamCapture.startRunning()
        
        // Add gesture support
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
        viewController.view.addGestureRecognizer(tapGesture)
        
        let button1 = createButton(withTitle: "1", target: context.coordinator, 
                                   action: #selector(context.coordinator.handleButton1(_:)))
        let button2 = createButton(withTitle: "2", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton2(_:)))
        let button3 = createButton(withTitle: "3", target: context.coordinator,
                                   action: #selector(context.coordinator.handleButton3(_:)))

        viewController.view.addSubview(button1)
        viewController.view.addSubview(button2)
        viewController.view.addSubview(button3)

        button1.translatesAutoresizingMaskIntoConstraints = false
        button2.translatesAutoresizingMaskIntoConstraints = false
        button3.translatesAutoresizingMaskIntoConstraints = false

        // Define the layout constraints
        NSLayoutConstraint.activate([
            button1.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button1.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: -70),
            button1.widthAnchor.constraint(equalToConstant: 50),
            button1.heightAnchor.constraint(equalToConstant: 50),

            button2.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button2.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            button2.widthAnchor.constraint(equalToConstant: 50),
            button2.heightAnchor.constraint(equalToConstant: 50),

            button3.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button3.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: 70),
            button3.widthAnchor.constraint(equalToConstant: 50),
            button3.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update the UI view controller if needed
    }
    
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
