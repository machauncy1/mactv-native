import AVFoundation
import CoreVideo

// Explicit CLI verification only; never scans the user's media library or
// produces sound. Decode actual video frames and a PCM audio buffer.
enum MediaProbe {
    static func run(path:String) -> Bool {
        do {
            let asset=AVURLAsset(url:URL(fileURLWithPath:path))
            guard let video=asset.tracks(withMediaType:.video).first else {throw ProbeError.noVideo}
            let reader=try AVAssetReader(asset:asset)
            let output=AVAssetReaderTrackOutput(track:video,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            guard reader.canAdd(output) else {throw ProbeError.noVideo}
            reader.add(output)
            var audioOutput:AVAssetReaderTrackOutput?
            if let audio=asset.tracks(withMediaType:.audio).first {
                let a=AVAssetReaderTrackOutput(track:audio,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsNonInterleaved:false])
                guard reader.canAdd(a) else {throw ProbeError.audio}
                reader.add(a);audioOutput=a
            }
            guard reader.startReading() else {throw reader.error ?? ProbeError.noVideo}
            var frames=0,width=0,height=0
            for _ in 0..<10 {
                guard let sample=output.copyNextSampleBuffer(),let image=CMSampleBufferGetImageBuffer(sample) else {break}
                frames+=1;width=CVPixelBufferGetWidth(image);height=CVPixelBufferGetHeight(image)
            }
            guard frames>0 else {throw reader.error ?? ProbeError.noVideo}
            var audioSamples=0
            if let audioOutput {
                guard let buffer=audioOutput.copyNextSampleBuffer() else {throw reader.error ?? ProbeError.audio}
                audioSamples=CMSampleBufferGetNumSamples(buffer)
                guard audioSamples>0 else {throw ProbeError.audio}
            }
            reader.cancelReading()
            print("PASS: decoded \(frames) video frames (\(width)×\(height)), \(audioSamples) PCM audio samples")
            return true
        } catch {
            fputs("Media decode verification failed: \(error.localizedDescription)\n",stderr)
            return false
        }
    }
    private enum ProbeError:Error {case noVideo,audio}
}
