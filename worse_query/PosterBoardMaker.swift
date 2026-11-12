import AVFoundation
import CoreImage
import Foundation
import UIKit

// MARK: - PosterBoard wallpaper maker
//
// Builds a PosterBoard wallpaper descriptor on-device from a photo
// or a video, then hands the finished folder to PosterBoardManager
// for install (same grant / copy / verify / receipt path as a
// .tendies import, so a made wallpaper can be listed and deleted
// exactly like an imported one).
//
// Format (verified against Pocket Poster, leminlimez, GPL-3.0 —
// its VideoHandler.createCaml is the recipe this builder follows,
// and its blank Floating layer + providerInfo blob ship in
// PosterBoardTemplate.swift; CAPlayground's template verified the
// descriptor layout):
//   - video: AVAssetReader frames (32BGRA) -> JPEG 0.7 assets,
//     main.caml with a CAKeyframeAnimation on "contents"
//     (beginTime 1e-100, repeatCount inf), index.xml with the real
//     pixel size. First 12 seconds only, sampled at most 30 fps.
//   - photo: the same builder with a single still frame.
//   - descriptor: CollectionsPoster extension, fresh random ID
//     9999...99999 (same range installers randomize to), folder
//     and file names derived from the device's screen class
//     (e.g. 390w-844h@3x~iphone), so the wallpaper belongs to
//     this device instead of the template's iPad class.
// A still photo as a one-frame animation is the natural adaptation
// of the video path — it has not been device-tested yet, and the
// maker says so in the Log when one is built.

enum PosterBoardMakerError: LocalizedError {
    case noVideoTrack
    case noFrames
    case photoUnreadable
    case templateMissing

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found in this file."
        case .noFrames: return "No frames could be read from this video."
        case .photoUnreadable: return "This photo could not be read."
        case .templateMissing: return "The wallpaper template is missing from the app."
        }
    }
}

enum PosterBoardMaker {
    static let maxVideoDuration = 12.0
    static let maxSampleFPS = 30.0
    static let maxLongEdge = 1920
    static let collectionsExtension = "com.apple.WallpaperKit.CollectionsPoster"

    // MARK: Screen class

    /// "390w-844h@3x~iphone" style class for this device, from
    /// its native bounds — Placard computes it the same way at
    /// runtime instead of hardcoding the template's class.
    static func screenClass() -> String {
        let screen = UIScreen.main
        let native = screen.nativeBounds.size
        let scale = Int(screen.nativeScale)
        let pointsW = Int((native.width / CGFloat(scale)).rounded())
        let pointsH = Int((native.height / CGFloat(scale)).rounded())
        let idiom = screen.traitCollection.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        return "\(pointsW)w-\(pointsH)h@\(scale)x~\(idiom)"
    }

    // MARK: Build

    /// Builds a complete descriptor folder in a fresh temp dir and
    /// returns its URL. `photo` and `videoURL` are mutually
    /// exclusive; exactly one must be set.
    static func buildDescriptor(
        name: String,
        photo: UIImage?,
        videoURL: URL?,
        loop: Bool,
        progress: @escaping (String) -> Void
    ) throws -> URL {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? "Custom" : cleanName
        let wallpaperID = Int.random(in: 9999...99999)
        let screenClass = screenClass()
        let wallpaperFolderName = "\(wallpaperID).Custom-\(screenClass).wallpaper"
        let backgroundName = "\(wallpaperID).Custom_Background-\(screenClass).ca"
        let floatingName = "\(wallpaperID).Custom_Floating-\(screenClass).ca"

        let fm = FileManager.default
        let descriptor = fm.temporaryDirectory
            .appendingPathComponent("wallpaper-maker-\(UUID().uuidString)", isDirectory: true)
        let contents = descriptor
            .appendingPathComponent("versions/1/contents", isDirectory: true)
        let wallpaperDir = contents.appendingPathComponent(wallpaperFolderName, isDirectory: true)
        let backgroundDir = wallpaperDir.appendingPathComponent(backgroundName, isDirectory: true)
        let floatingDir = wallpaperDir.appendingPathComponent(floatingName, isDirectory: true)
        let assetsDir = backgroundDir.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: floatingDir, withIntermediateDirectories: true)

        // Frames -> assets/ + the animation that plays them.
        let frames: (count: Int, width: Int, height: Int, duration: Double)
        if let photo {
            frames = try writePhotoFrames(photo, to: assetsDir)
            print("[PosterBoard] photo wallpaper: single still frame (unverified on device — please report whether it shows in the gallery)")
        } else if let videoURL {
            frames = try writeVideoFrames(videoURL: videoURL, to: assetsDir, progress: progress)
        } else {
            throw PosterBoardMakerError.photoUnreadable
        }
        guard frames.count > 0 else { throw PosterBoardMakerError.noFrames }

        try mainCaml(width: frames.width, height: frames.height, frameCount: frames.count, duration: frames.duration, loop: loop)
            .data(using: .utf8)?.write(to: backgroundDir.appendingPathComponent("main.caml"))
        try indexXml(width: frames.width, height: frames.height)
            .data(using: .utf8)?.write(to: backgroundDir.appendingPathComponent("index.xml"))
        try PosterBoardTemplate.assetManifestCaml.data(using: .utf8)?
            .write(to: backgroundDir.appendingPathComponent("assetManifest.caml"))

        // Blank Floating layer, verbatim from the template.
        try PosterBoardTemplate.floatingMainCaml.data(using: .utf8)?
            .write(to: floatingDir.appendingPathComponent("main.caml"))
        try PosterBoardTemplate.floatingIndexXml.data(using: .utf8)?
            .write(to: floatingDir.appendingPathComponent("index.xml"))
        try PosterBoardTemplate.assetManifestCaml.data(using: .utf8)?
            .write(to: floatingDir.appendingPathComponent("assetManifest.caml"))

        // Descriptor identity files.
        try String(wallpaperID).data(using: .utf8)?
            .write(to: descriptor.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"))
        try "PRPosterRoleLockScreen".data(using: .utf8)?
            .write(to: descriptor.appendingPathComponent("com.apple.posterkit.role.identifier"))
        guard let providerInfo = Data(base64Encoded: PosterBoardTemplate.providerInfoBase64) else {
            throw PosterBoardMakerError.templateMissing
        }
        try providerInfo.write(to: descriptor.appendingPathComponent("providerInfo.plist"))

        // Wallpaper.plist + contents userInfo, with this
        // wallpaper's own name, ID and screen class.
        let wallpaperPlist: [String: Any] = [
            "appearanceAware": true,
            "assets": ["lockAndHome": ["default": [
                "backgroundAnimationFileName": backgroundName,
                "floatingAnimationFileNameKey": floatingName,
                "identifier": wallpaperID,
                "name": displayName,
                "type": "LayeredAnimation",
            ]]],
            "contentVersion": 2.01,
            "family": "Custom",
            "identifier": wallpaperID,
            "logicalScreenClass": screenClass,
            "name": displayName,
            "preferredProminentColor": ["dark": "#00000", "default": "#FFFFFF"],
            "version": 1,
        ]
        let wallpaperData = try PropertyListSerialization.data(fromPropertyList: wallpaperPlist, format: .xml, options: 0)
        try wallpaperData.write(to: wallpaperDir.appendingPathComponent("Wallpaper.plist"))

        let userInfo: [String: Any] = [
            "posterEnvironmentOverrides": Data("{}".utf8),
            "wallpaperRepresentingFileName": wallpaperFolderName,
            "wallpaperRepresentingIdentifier": wallpaperID,
        ]
        let userInfoData = try PropertyListSerialization.data(fromPropertyList: userInfo, format: .xml, options: 0)
        try userInfoData.write(to: contents.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo"))

        print("[PosterBoard] built “\(displayName)” (\(frames.count) frame(s), \(frames.width)x\(frames.height), id \(wallpaperID))")
        return descriptor
    }

    // MARK: Photo frames

    private static func writePhotoFrames(_ photo: UIImage, to assetsDir: URL) throws -> (count: Int, width: Int, height: Int, duration: Double) {
        guard let cgImage = photo.cgImage else { throw PosterBoardMakerError.photoUnreadable }
        let scaled = scaledImage(cgImage, maxLongEdge: maxLongEdge)
        guard let data = UIImage(cgImage: scaled).jpegData(compressionQuality: 0.9) else {
            throw PosterBoardMakerError.photoUnreadable
        }
        try data.write(to: assetsDir.appendingPathComponent("0.jpg"))
        return (1, scaled.width, scaled.height, 1.0)
    }

    // MARK: Video frames

    private static func writeVideoFrames(videoURL: URL, to assetsDir: URL, progress: @escaping (String) -> Void) throws -> (count: Int, width: Int, height: Int, duration: Double) {
        let asset = AVURLAsset(url: videoURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw PosterBoardMakerError.noVideoTrack
        }
        let preferredTransform = track.preferredTransform
        let natural = track.naturalSize.applying(preferredTransform)
        let fps = Double(track.nominalFrameRate)
        guard fps > 0 else { throw PosterBoardMakerError.noVideoTrack }

        // Sample at most 30 fps: a 12 s 60 fps video would
        // otherwise be 720 JPEGs. Trim to the first 12 s.
        let keepEvery = max(1, Int(ceil(fps / maxSampleFPS)))
        let sampleFPS = fps / Double(keepEvery)
        let maxFrames = Int(maxVideoDuration * sampleFPS)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ])
        reader.add(output)
        reader.startReading()

        let context = CIContext()
        var frameIndex = 0
        var written = 0
        var outWidth = 0
        var outHeight = 0
        while let sample = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            if CMTimeGetSeconds(timestamp) > maxVideoDuration { break }
            if written >= maxFrames { break }
            defer { frameIndex += 1 }
            guard frameIndex % keepEvery == 0 else { continue }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                .transformed(by: preferredTransform)
            let extent = ciImage.extent
            let scale = min(1.0, CGFloat(maxLongEdge) / max(extent.width, extent.height))
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent),
                  let jpg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) else { continue }
            try jpg.write(to: assetsDir.appendingPathComponent("\(written).jpg"))
            outWidth = cgImage.width
            outHeight = cgImage.height
            written += 1
            if written % 30 == 0 {
                progress("Frame \(written)…")
            }
        }
        guard written > 0 else { throw PosterBoardMakerError.noFrames }
        return (written, outWidth, outHeight, Double(written) / sampleFPS)
    }

    private static func scaledImage(_ image: CGImage, maxLongEdge: Int) -> CGImage {
        let scale = min(1.0, CGFloat(maxLongEdge) / CGFloat(max(image.width, image.height)))
        guard scale < 1.0 else { return image }
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: CAML + index.xml (Pocket Poster templates, parameterized)

    private static func mainCaml(width: Int, height: Int, frameCount: Int, duration: Double, loop: Bool) -> String {
        let halfW = width / 2
        let halfH = height / 2
        var values = ""
        for i in 0..<frameCount {
            values += "\t\t\t<CGImage src=\"assets/\(i).jpg\"/>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        
        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
        <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_FLOATING" position="\(halfW) \(halfH)">
        <sublayers>
        <CATransformLayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" allowsHitTesting="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Chip" position="\(halfW) \(halfH)">
        <sublayers>
        <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="CALayer1" position="\(halfW) \(halfH)">
        <contents type="CGImage" src="assets/0.jpg"/>
        <animations>
        <animation type="CAKeyframeAnimation" calculationMode="linear" keyPath="contents" beginTime="1e-100" duration="\(duration)" removedOnCompletion="0" repeatCount="inf" repeatDuration="0" speed="1" timeOffset="0" autoreverses="\(loop ? 1 : 0)">
        <values>
        \(values)        </values>
        </animation>
          </animations>
        </CALayer>
        </sublayers>
        </CATransformLayer>
        </sublayers>
        <states>
        <LKState name="Locked">
        <elements/>
        </LKState>
        <LKState name="Unlock">
        <elements/>
        </LKState>
        <LKState name="Sleep">
        <elements/>
        </LKState>
        </states>
        <stateTransitions>
        <LKStateTransition fromState="*" toState="Unlock">
        <elements/>
        </LKStateTransition>
        <LKStateTransition fromState="Unlock" toState="*">
        <elements/>
        </LKStateTransition>
        <LKStateTransition fromState="*" toState="Locked">
        <elements/>
        </LKStateTransition>
        <LKStateTransition fromState="Locked" toState="*">
        <elements/>
        </LKStateTransition>
        <LKStateTransition fromState="*" toState="Sleep">
        <elements/>
        </LKStateTransition>
        <LKStateTransition fromState="Sleep" toState="*">
        <elements/>
        </LKStateTransition>
        </stateTransitions>
        </CALayer>
        </caml>
        """
    }

    private static func indexXml(width: Int, height: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>assetManifest</key>
            <string>assetManifest.caml</string>
            <key>documentHeight</key>
            <real>\(height)</real>
            <key>documentResizesToView</key>
            <true/>
            <key>documentWidth</key>
            <real>\(width)</real>
            <key>dynamicGuidesEnabled</key>
            <true/>
            <key>geometryFlipped</key>
            <false/>
            <key>guidesEnabled</key>
            <true/>
            <key>interactiveMouseEventsEnabled</key>
            <true/>
            <key>interactiveShowsCursor</key>
            <true/>
            <key>interactiveTouchEventsEnabled</key>
            <false/>
            <key>loopEnd</key>
            <real>0.0</real>
            <key>loopStart</key>
            <real>0.0</real>
            <key>loopingEnabled</key>
            <false/>
            <key>multitouchDisablesMouse</key>
            <false/>
            <key>multitouchEnabled</key>
            <false/>
            <key>presentationMouseEventsEnabled</key>
            <true/>
            <key>presentationShowsCursor</key>
            <true/>
            <key>presentationTouchEventsEnabled</key>
            <false/>
            <key>rootDocument</key>
            <string>main.caml</string>
            <key>savesWindowFrame</key>
            <false/>
            <key>scalesToFitInPlayer</key>
            <true/>
            <key>showsTouches</key>
            <true/>
            <key>snappingEnabled</key>
            <true/>
            <key>timelineMarkers</key>
            <string>[(null)]</string>
            <key>touchesColor</key>
            <string>1 1 0 0.8</string>
            <key>unitsInPixelsInPlayer</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
