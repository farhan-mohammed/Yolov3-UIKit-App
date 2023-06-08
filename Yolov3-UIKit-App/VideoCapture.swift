//
//  VideoCapture.swift
//  Yolov3-UIKit-App
//
//  Created by Farhan Mohammed on 2023-05-29.
//

import UIKit
import AVFoundation
import CoreVideo

/// Delegate protocol for receiving video capture frames and timestamps.
public protocol VideoCaptureDelegate: AnyObject {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
}

/// Class responsible for capturing video frames from the device's camera.
public class VideoCapture: NSObject {
    public var previewLayer: AVCaptureVideoPreviewLayer? // Preview layer to display the captured video.
    public weak var delegate: VideoCaptureDelegate? // Delegate to receive captured video frames.
    public var fps = 10 // Desired frames per second (FPS) for capturing.
    
    let captureSession = AVCaptureSession() // The capture session.
    let videoOutput = AVCaptureVideoDataOutput() // Output for video data.
    let queue = DispatchQueue(label: "net.machinethink.camera-queue") // Queue for handling video capture callbacks.
    var lastTimestamp = CMTime() // Timestamp of the last captured frame.
    
    /// Set up the video capture.
    public func setUp(sessionPreset: AVCaptureSession.Preset = .medium, completion: @escaping (Bool) -> Void) {
        queue.async {
            let success = self.setUpCamera(sessionPreset: sessionPreset)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    private func setUpCamera(sessionPreset: AVCaptureSession.Preset) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        
        // Check if the device has a video capture device available.
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            print("Error: no video devices available")
            return false
        }
        
        // Create AVCaptureDeviceInput using the capture device.
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Error: could not create AVCaptureDeviceInput")
            return false
        }
        
        // Add the video input to the capture session.
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        // Create a preview layer and configure its properties.
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer
        
        // Configure video output settings.
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
        ]
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        
        // Add the video output to the capture session.
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Set the video orientation to portrait.
        videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
        
        captureSession.commitConfiguration()
        
        return true
    }
    
    /// Start capturing video frames.
    public func start() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    /// Stop capturing video frames.
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Because lowering the capture device's FPS looks ugly in the preview,
        // we capture at full speed but only call the delegate at its desired
        // framerate.
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let deltaTime = timestamp - self.lastTimestamp
        if deltaTime >= CMTimeMake(value: 1, timescale: Int32(fps)) {
            self.lastTimestamp = timestamp
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            print("fps\(timestamp)")
            delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("dropped frame")
    }
}
