//
//  ViewController.swift
//  Yolov3-UIKit-App
//
//  Created by Farhan Mohammed on 2023-05-29.
//

import UIKit
import Vision
import AVFoundation
import CoreMedia
import VideoToolbox

class ViewController: UIViewController {
    // Constants
    let labelHeight: CGFloat = 50.0
    
    // Video capture and prediction
    var videoCapture: VideoCapture!
    var request: VNCoreMLRequest!
    var startTimes: [CFTimeInterval] = []
    let yolo = YOLO()
    
    // Bounding boxes and colors
    var boundingBoxes = [BoundingBox]()
    var colors: [UIColor] = []
    
    // Core Image
    let ciContext = CIContext()
    var resizedPixelBuffer: CVPixelBuffer?
    
    // Frame processing
    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    let semaphore = DispatchSemaphore(value: 2)
    
    // UI elements
    let timeLabel: UILabel = {
        let label = UILabel()
        return label
    }()
    
    let videoPreview: UIView = {
        let view = UIView()
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up time label and video preview
        timeLabel.frame = CGRect(x: 0, y: UIScreen.main.bounds.size.height - labelHeight, width: UIScreen.main.bounds.size.width, height: labelHeight)
        videoPreview.frame = self.view.frame
        view.addSubview(timeLabel)
        view.addSubview(videoPreview)
        
        // Set up bounding boxes and colors
        setUpBoundingBoxes()
        
        // Set up Core Image
        setUpCoreImage()
        
        // Set up camera
        setUpCamera()
        
        // Set initial text for time label
        timeLabel.text = ""
    }
    
    // Set up Core Image for resizing pixel buffer
    func setUpCoreImage() {
        let status = CVPixelBufferCreate(nil, YOLO.inputWidth, YOLO.inputHeight, kCVPixelFormatType_32BGRA, nil, &resizedPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create resized pixel buffer", status)
        }
    }
    
    // Set up bounding boxes and colors
    func setUpBoundingBoxes() {
        for _ in 0..<YOLO.maxBoundingBoxes {
            boundingBoxes.append(BoundingBox())
        }
        
        // Generate colors for the bounding boxes
        for r: CGFloat in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0] {
            for g: CGFloat in [0.3, 0.5, 0.7, 0.9] {
                for b: CGFloat in [0.4, 0.6, 0.8] {
                    let color = UIColor(red: r, green: g, blue: b, alpha: 1)
                    colors.append(color)
                }
            }
        }
    }
    
    // Set up the camera capture
    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 50
        
        videoCapture.setUp(sessionPreset: AVCaptureSession.Preset.vga640x480) { success in
            if success {
                // Add the video preview into the UI
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                
                // Add the bounding box layers to the UI, on top of the video preview
                DispatchQueue.main.async {
                    let boxes = self.boundingBoxes
                    let videoLayer = self.videoPreview.layer
                    if boxes != nil && videoLayer != nil {
                        for box in boxes {
                            box.addToLayer(videoLayer)
                        }
                        self.semaphore.signal()
                    }
                }
                
                // Start capturing live video
                self.videoCapture.start()
            }
        }
    }
    
  
    
    // Measure the frames per second (FPS) rate
    func measureFPS() -> Double {
        // Measure the time elapsed for capturing frames
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        
        // Reset the frame counter and start time after 1 second
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        
        return currentFPSDelivered
    }
    
    // Handle memory warnings
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

//MARK: - Model Methods
extension ViewController {
    
    
    // Perform prediction on a pixel buffer
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure the prediction time
        let startTime = CACurrentMediaTime()
        
        // Resize the input with Core Image to match the required input size
        guard let resizedPixelBuffer = resizedPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = CGFloat(YOLO.inputWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY = CGFloat(YOLO.inputHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        ciContext.render(scaledImage, to: resizedPixelBuffer)
        
        // Perform the prediction with YOLO model
        if let boundingBoxes = try? yolo.predict(image: resizedPixelBuffer) {
            let elapsed = CACurrentMediaTime() - startTime
            showOnMainThread(boundingBoxes, elapsed)
        }
    }
    
    // Display bounding boxes and update time label on the main thread
    func showOnMainThread(_ boundingBoxes: [YOLO.Prediction], _ elapsed: CFTimeInterval) {
        weak var weakSelf = self
        
        DispatchQueue.main.async {
            weakSelf?.show(predictions: boundingBoxes)
            
            guard let fps = weakSelf?.measureFPS() else { return }
            weakSelf?.timeLabel.text = String(format: "Elapsed %.5f seconds - %.2f FPS", elapsed, fps)
            
            weakSelf?.semaphore.signal()
        }
    }
    
    // Show the bounding boxes on the video preview
    func show(predictions: [YOLO.Prediction]) {
        for i in 0..<boundingBoxes.count {
            if i < predictions.count {
                let prediction = predictions[i]
                
                // Calculate the position and size of the bounding box on the video preview
                let width = view.bounds.width
                let height = width * 4 / 3
                let scaleX = width / CGFloat(YOLO.inputWidth)
                let scaleY = height / CGFloat(YOLO.inputHeight)
                let top = (view.bounds.height - height) / 2
                
                // Translate and scale the rectangle to fit the video preview
                var rect = prediction.rect
                rect.origin.x *= scaleX
                rect.origin.y *= scaleY
                rect.origin.y += top
                rect.size.width *= scaleX
                rect.size.height *= scaleY
                
                // Show the bounding box
                let label = String(format: "%@ %.1f", labels[prediction.classIndex], prediction.score)
                let color = colors[prediction.classIndex]
                boundingBoxes[i].show(frame: rect, label: label, color: color)
            } else {
                boundingBoxes[i].hide()
            }
        }
    }
}

//MARK: - UI Configuration
extension ViewController{
    // Resize the preview layer to fit the video preview
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    // Override the preferred status bar style
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // Update the layout of subviews
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizePreviewLayer()
    }
}

//MARK: - VideoCaptureDelegate
extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        weak var weakSelf = self
        
        if let pixelBuffer = pixelBuffer {
            // Perform the prediction on a background queue to improve throughput
            DispatchQueue.global().async {
                weakSelf?.predict(pixelBuffer: pixelBuffer)
            }
        }
    }
}
