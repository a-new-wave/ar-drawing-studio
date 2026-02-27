import Foundation
import AVFoundation
import UIKit
import Photos

class TimelapseEncoder {
    
    /// Processes a video at `videoPath` to 2.5x speed and saves to Camera Roll.
    static func process(videoPath: String, completion: @escaping (Bool, String?) -> Void) {
        let inputURL = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: inputURL)
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let assetTrack = asset.tracks(withMediaType: .video).first else {
            completion(false, "Could not create composition/asset track")
            return
        }
        
        do {
            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)
            
            // 2.5x speed = 0.4x duration
            let targetDuration = CMTimeMultiplyByFloat64(asset.duration, multiplier: 0.4)
            compositionTrack.scaleTimeRange(timeRange, toDuration: targetDuration)
            
            // Maintain orientation
            compositionTrack.preferredTransform = assetTrack.preferredTransform
            
            let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent("processed_timelapse.mp4")
            try? FileManager.default.removeItem(at: outputURL)
            
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                completion(false, "Could not create export session")
                return
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            
            exportSession.exportAsynchronously {
                if exportSession.status == .completed {
                    saveToCameraRoll(url: outputURL, completion: completion)
                } else {
                    completion(false, exportSession.error?.localizedDescription ?? "Export failed")
                }
            }
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    private static func saveToCameraRoll(url: URL, completion: @escaping (Bool, String?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            let isAuthorized: Bool
            if #available(iOS 14, *) {
                isAuthorized = (status == .authorized || status == .limited)
            } else {
                isAuthorized = (status == .authorized)
            }
            
            guard isAuthorized else {
                completion(false, "Photo library access denied")
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { saved, error in
                completion(saved, error?.localizedDescription)
            }
        }
    }
}
