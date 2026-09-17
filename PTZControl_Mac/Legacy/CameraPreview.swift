//
//  CameraPreview.swift
//  PTZControlMac
//
//  Camera preview view using AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation
import AppKit

struct CameraPreview: NSViewRepresentable {
    let camera: Camera
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        // Create capture session
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        
        do {
            // Add camera input
            let input = try AVCaptureDeviceInput(device: camera.device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Create preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer = previewLayer
            
            // Start session on dedicated serial queue
            context.coordinator.sessionQueue.async {
                session.startRunning()
            }
            
            // Store session in context
            context.coordinator.session = session
            context.coordinator.previewLayer = previewLayer
            
        } catch {
            print("Error setting up camera preview: \(error.localizedDescription)")
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update preview layer frame when view size changes
        if let layer = context.coordinator.previewLayer {
            layer.frame = nsView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        let sessionQueue = DispatchQueue(label: "com.ptzcontrol.camera.session")
        
        deinit {
            // Stop session synchronously to ensure proper cleanup
            session?.stopRunning()
        }
    }
}

// Preview wrapper with no camera state
struct CameraPreviewView: View {
    let camera: Camera?
    
    var body: some View {
        if let camera = camera {
            CameraPreview(camera: camera)
                .frame(height: 120)
                .cornerRadius(8)
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 120)
                    .cornerRadius(8)
                
                VStack(spacing: 4) {
                    Image(systemName: "video.slash")
                        .font(.title)
                        .foregroundColor(.gray)
                    Text("No Camera")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
