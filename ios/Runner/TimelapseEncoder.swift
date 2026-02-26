import Foundation
import AVFoundation
import UIKit
import Photos

class TimelapseEncoder {
    
    /// Stitches JPEG frames in `framesDir` into a 4fps MP4 at `outputPath`,
    /// then saves it to the Camera Roll.
    static func encode(framesDir: String, frameCount: Int, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outputURL = URL(fileURLWithPath: framesDir).appendingPathComponent("timelapse.mp4")
            
            // Remove any existing file
            try? FileManager.default.removeItem(at: outputURL)
            
            // Determine frame size from the first frame
            let firstFramePath = String(format: "\(framesDir)/frame_%04d.jpg", 0)
            guard let firstImage = UIImage(contentsOfFile: firstFramePath),
                  let cgImage = firstImage.cgImage else {
                completion(false, "Could not read first frame")
                return
            }
            
            let width  = cgImage.width  % 2 == 0 ? cgImage.width  : cgImage.width  - 1
            let height = cgImage.height % 2 == 0 ? cgImage.height : cgImage.height - 1
            let frameSize = CGSize(width: width, height: height)
            
            // AVAssetWriter setup
            guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
                completion(false, "AVAssetWriter init failed")
                return
            }
            
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: NSNumber(value: width),
                AVVideoHeightKey: NSNumber(value: height),
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                ]
            )
            
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            // 4 fps timelapse
            let fps: Int32 = 4
            let timescale: Int32 = 600
            let frameDuration = CMTimeMake(value: Int64(timescale / fps), timescale: timescale)
            
            for i in 0..<frameCount {
                let framePath = String(format: "\(framesDir)/frame_%04d.jpg", i)
                guard let image = UIImage(contentsOfFile: framePath),
                      let buffer = pixelBuffer(from: image, size: frameSize) else { continue }
                
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
                
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
            
            input.markAsFinished()
            writer.finishWriting {
                guard writer.status == .completed else {
                    completion(false, writer.error?.localizedDescription)
                    return
                }
                // Save to Camera Roll
                PHPhotoLibrary.requestAuthorization { status in
                    guard status == .authorized || status == .limited else {
                        completion(false, "Photo library access denied")
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                    }) { saved, error in
                        completion(saved, error?.localizedDescription)
                    }
                }
            }
        }
    }
    
    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buf = buffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buf, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        context?.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }
}
