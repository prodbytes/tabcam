import AVFoundation
import Flutter
import ImageIO
import QuartzCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var takeOverlayChannel: FlutterMethodChannel?
  private var videoEditChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TakeOverlay") {
      let channel = FlutterMethodChannel(
        name: "tabcam/take_overlay", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(TakeOverlay.handle)
      takeOverlayChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VideoEdit") {
      let channel = FlutterMethodChannel(
        name: "tabcam/video_edit", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(VideoEdit.handle)
      videoEditChannel = channel
    }
  }
}

/// Burns the tab's neckline bands into a recorded take (method channel
/// `tabcam/take_overlay`, method `burn`).
enum TakeOverlay {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "burn" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let reply: (Any?) -> Void = { value in
      DispatchQueue.main.async { result(value) }
    }
    guard let args = call.arguments as? [String: Any],
      let input = args["input"] as? String,
      let output = args["output"] as? String,
      let rawBands = args["bands"] as? [Any]
    else {
      reply(FlutterError(code: "failed", message: "Bad arguments for burn.", details: nil))
      return
    }
    var bands: [TakeOverlayBurner.Band] = []
    for raw in rawBands {
      guard let band = raw as? [String: Any],
        let start = (band["startMs"] as? NSNumber)?.int64Value,
        let png = band["png"] as? FlutterStandardTypedData
      else {
        reply(FlutterError(code: "failed", message: "Bad band in burn.", details: nil))
        return
      }
      let end = (band["endMs"] as? NSNumber)?.int64Value
      bands.append(TakeOverlayBurner.Band(startMs: start, endMs: end, png: png.data))
    }
    TakeOverlayBurner.burn(
      input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output), bands: bands
    ) { error in
      if let error = error {
        reply(FlutterError(code: "failed", message: error, details: nil))
      } else {
        reply(output)
      }
    }
  }
}

/// The AVFoundation side of the overlay, free of Flutter and UIKit.
enum TakeOverlayBurner {
  struct Band {
    let startMs: Int64
    /// nil: shown to the end of the video.
    let endMs: Int64?
    let png: Data
  }

  /// Calls `completion` exactly once, on any thread, with nil on success or
  /// an error message.
  static func burn(
    input: URL, output: URL, bands: [Band], completion: @escaping (String?) -> Void
  ) {
    Task {
      do {
        try await run(input: input, output: output, bands: bands)
        completion(nil)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }

  private struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  private static func run(input: URL, output: URL, bands: [Band]) async throws {
    let asset = AVURLAsset(url: input)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      throw Failure("The video has no video track.")
    }
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let (timeRange, naturalSize, transform, frameRate) = try await videoTrack.load(
      .timeRange, .naturalSize, .preferredTransform, .nominalFrameRate)
    guard naturalSize.width > 0, naturalSize.height > 0, timeRange.duration.seconds > 0 else {
      throw Failure("The video is empty.")
    }

    let composition = AVMutableComposition()
    guard
      let compVideo = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw Failure("Could not add the video track.") }
    try compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)
    for audio in audioTracks {
      let audioRange = try await audio.load(.timeRange)
      let range = CMTimeRangeGetIntersection(audioRange, otherRange: timeRange)
      guard range.duration > .zero,
        let compAudio = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { continue }
      try compAudio.insertTimeRange(range, of: audio, at: range.start - timeRange.start)
    }

    // The frame as displayed: the transform rotates (and maybe mirrors) the
    // natural frame; its bounding box is moved back to the origin.
    let shown = CGRect(origin: .zero, size: naturalSize).applying(transform)
    let renderSize = CGSize(width: evenRound(shown.width), height: evenRound(shown.height))
    let layerTransform = transform.concatenating(
      CGAffineTransform(translationX: -shown.minX, y: -shown.minY))

    let duration = timeRange.duration
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
    layerInstruction.setTransform(layerTransform, at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    let fps = frameRate > 0 ? frameRate : 30
    videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
    videoComposition.instructions = [instruction]

    // Core Animation in a video composition has its origin at the bottom
    // left, so y = 0 is the bottom of the frame.
    let frame = CGRect(origin: .zero, size: renderSize)
    let parent = CALayer()
    parent.frame = frame
    let videoLayer = CALayer()
    videoLayer.frame = frame
    parent.addSublayer(videoLayer)
    let total = duration.seconds
    for band in bands {
      let start = max(0, Double(band.startMs) / 1000)
      let end = min(total, band.endMs.map { Double($0) / 1000 } ?? total)
      guard end > start else { continue }
      guard let source = CGImageSourceCreateWithData(band.png as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        image.width > 0
      else { throw Failure("A band is not a valid PNG.") }
      let height = renderSize.width * CGFloat(image.height) / CGFloat(image.width)
      let layer = CALayer()
      layer.frame = CGRect(x: 0, y: 0, width: renderSize.width, height: height)
      layer.contents = image
      layer.contentsGravity = .resize
      layer.opacity = 0
      let show = CABasicAnimation(keyPath: "opacity")
      show.fromValue = 1
      show.toValue = 1
      show.beginTime = AVCoreAnimationBeginTimeAtZero + start
      show.duration = end - start
      show.isRemovedOnCompletion = false
      // Outside [start, end) the animation has no effect: opacity stays 0.
      show.fillMode = .removed
      layer.add(show, forKey: "show")
      parent.addSublayer(layer)
    }
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer, in: parent)

    if FileManager.default.fileExists(atPath: output.path) {
      try FileManager.default.removeItem(at: output)
    }
    guard
      let export = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else { throw Failure("Could not start the export.") }
    export.outputURL = output
    export.outputFileType = .mp4
    export.videoComposition = videoComposition
    export.shouldOptimizeForNetworkUse = true
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      export.exportAsynchronously { done.resume() }
    }
    guard export.status == .completed else {
      throw Failure(export.error?.localizedDescription ?? "The export did not complete.")
    }
  }

  /// Rounds a render dimension to an even number of pixels, as H.264 wants.
  private static func evenRound(_ value: CGFloat) -> CGFloat {
    let rounded = Int(abs(value).rounded())
    return CGFloat(max(2, rounded + rounded % 2))
  }
}

/// Basic edits of a video (method channel `tabcam/video_edit`, method
/// `edit`): the part kept (`startMs`–`endMs`), and its sound (`sound`):
/// `original` kept, `none` removed, or `track` replaced by the sound file at
/// `track`: `gapMs` of silence, then the track from `fromMs` to `toMs` (the
/// app works out what fits; left out when nothing does). Replies with the
/// output path.
enum VideoEdit {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "edit" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let reply: (Any?) -> Void = { value in
      DispatchQueue.main.async { result(value) }
    }
    guard let args = call.arguments as? [String: Any],
      let input = args["input"] as? String,
      let output = args["output"] as? String,
      let startMs = (args["startMs"] as? NSNumber)?.int64Value,
      let endMs = (args["endMs"] as? NSNumber)?.int64Value
    else {
      reply(FlutterError(code: "failed", message: "Bad arguments for edit.", details: nil))
      return
    }
    let sound = args["sound"] as? String ?? "original"
    let track = (args["track"] as? String).map { URL(fileURLWithPath: $0) }
    var part: VideoEditor.TrackPart?
    if let gapMs = (args["gapMs"] as? NSNumber)?.int64Value,
      let fromMs = (args["fromMs"] as? NSNumber)?.int64Value,
      let toMs = (args["toMs"] as? NSNumber)?.int64Value
    {
      part = VideoEditor.TrackPart(gapMs: gapMs, fromMs: fromMs, toMs: toMs)
    }
    if sound == "track" && track == nil {
      reply(FlutterError(code: "failed", message: "A new sound track needs a file.", details: nil))
      return
    }
    VideoEditor.edit(
      input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output),
      startMs: startMs, endMs: endMs, sound: sound, track: track, part: part
    ) { error in
      if let error = error {
        reply(FlutterError(code: "failed", message: error, details: nil))
      } else {
        reply(output)
      }
    }
  }
}

/// The AVFoundation side of the edit, free of Flutter and UIKit: an
/// `AVMutableComposition` of the kept part of the video (its orientation
/// kept as the track's transform) and the sound chosen, exported as H.264
/// and AAC in MP4.
enum VideoEditor {
  /// The part of the track that goes in: `gapMs` of silence from the kept
  /// part's start, then the track from `fromMs` to `toMs`.
  struct TrackPart {
    let gapMs: Int64
    let fromMs: Int64
    let toMs: Int64
  }

  /// Calls `completion` exactly once, on any thread, with nil on success or
  /// an error message.
  static func edit(
    input: URL, output: URL, startMs: Int64, endMs: Int64, sound: String, track: URL?,
    part: TrackPart?, completion: @escaping (String?) -> Void
  ) {
    Task {
      do {
        try await run(
          input: input, output: output, startMs: startMs, endMs: endMs, sound: sound,
          track: track, part: part)
        completion(nil)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }

  private struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  private static func run(
    input: URL, output: URL, startMs: Int64, endMs: Int64, sound: String, track: URL?,
    part: TrackPart?
  ) async throws {
    let asset = AVURLAsset(url: input)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      throw Failure("The video has no video track.")
    }
    let (trackRange, transform) = try await videoTrack.load(.timeRange, .preferredTransform)
    let wanted = CMTimeRange(
      start: CMTime(value: startMs, timescale: 1000), end: CMTime(value: endMs, timescale: 1000))
    let range = CMTimeRangeGetIntersection(wanted, otherRange: trackRange)
    guard range.duration > .zero else { throw Failure("Nothing to keep.") }

    let composition = AVMutableComposition()
    guard
      let compVideo = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw Failure("Could not add the video track.") }
    try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
    compVideo.preferredTransform = transform

    switch sound {
    case "original":
      for audio in try await asset.loadTracks(withMediaType: .audio) {
        let audioRange = CMTimeRangeGetIntersection(
          try await audio.load(.timeRange), otherRange: range)
        guard audioRange.duration > .zero,
          let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { continue }
        try compAudio.insertTimeRange(audioRange, of: audio, at: audioRange.start - range.start)
      }
    case "track":
      guard let track = track else { throw Failure("No track.") }
      guard let audio = try await AVURLAsset(url: track).loadTracks(withMediaType: .audio).first
      else { throw Failure("The track has no sound.") }
      let audioRange = try await audio.load(.timeRange)
      // Nothing of the track falls in the kept part: silence.
      if let part = part, part.toMs > part.fromMs, part.gapMs >= 0, part.fromMs >= 0 {
        let gap = CMTime(value: part.gapMs, timescale: 1000)
        let from = CMTimeMinimum(CMTime(value: part.fromMs, timescale: 1000), audioRange.duration)
        let to = CMTimeMinimum(CMTime(value: part.toMs, timescale: 1000), audioRange.duration)
        guard
          let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure("Could not add the sound track.") }
        try compAudio.insertTimeRange(
          CMTimeRange(start: audioRange.start + from, end: audioRange.start + to), of: audio,
          at: gap)
      }
    default:
      break
    }

    if FileManager.default.fileExists(atPath: output.path) {
      try FileManager.default.removeItem(at: output)
    }
    guard
      let export = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else { throw Failure("Could not start the export.") }
    export.outputURL = output
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      export.exportAsynchronously { done.resume() }
    }
    guard export.status == .completed else {
      throw Failure(export.error?.localizedDescription ?? "The export did not complete.")
    }
  }
}
