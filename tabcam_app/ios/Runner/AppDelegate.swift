import AVFoundation
import AudioToolbox
import Flutter
import ImageIO
import QuartzCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var takeOverlayChannel: FlutterMethodChannel?
  private var videoEditChannel: FlutterMethodChannel?
  private var soundChannel: FlutterMethodChannel?
  private var takeAudioChannel: FlutterMethodChannel?

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
      channel.setMethodCallHandler { [weak channel] call, result in
        VideoEdit.handle(call, result: result, channel: channel)
      }
      videoEditChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Sound") {
      let channel = FlutterMethodChannel(
        name: "tabcam/sound", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(Sound.handle)
      soundChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TakeAudio") {
      let channel = FlutterMethodChannel(
        name: "tabcam/audio", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(TakeAudio.handle)
      takeAudioChannel = channel
    }
  }
}

/// The app's audio session for Cam's takes (method channel `tabcam/audio`,
/// see lib/capture/take_priority.dart). `prepare`, when Cam opens and as a
/// take starts: play and record in the video recording mode (the
/// microphone by the camera, none of the voice processing of a call),
/// mixed with others (the song playing along, in the app or another,
/// goes on and isn't lowered), the speaker by default, Bluetooth and
/// AirPlay for the sound out (the camera plugin's own options, so it
/// changes nothing after), 48 kHz preferred. `release`, when Cam closes:
/// the mode back to the default, the category as the camera leaves it.
/// Each changes the session only where it differs, so a song playing
/// doesn't stutter.
enum TakeAudio {
  static let options: AVAudioSession.CategoryOptions = [
    .mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay,
  ]

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "prepare": try prepare()
      case "release": try release()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    } catch {
      result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
    }
  }

  static func prepare() throws {
    let session = AVAudioSession.sharedInstance()
    // Ducking others would lower the song playing along.
    let wanted = session.categoryOptions.union(options).subtracting(.duckOthers)
    if session.category != .playAndRecord || session.mode != .videoRecording
      || session.categoryOptions != wanted
    {
      try session.setCategory(.playAndRecord, mode: .videoRecording, options: wanted)
    }
    if session.preferredSampleRate != 48_000 {
      try? session.setPreferredSampleRate(48_000)
    }
    try session.setActive(true)
  }

  static func release() throws {
    let session = AVAudioSession.sharedInstance()
    guard session.mode != .default else { return }
    try session.setCategory(session.category, mode: .default, options: session.categoryOptions)
  }
}

/// Short sounds the app makes (Rescan's ding, see lib/sound/ding.dart):
/// method channel `tabcam/sound`, method `ding`, its argument the sound's
/// WAV file as bytes (the app makes it). Written to the temporary folder
/// and played as a system sound: at the system's volume, silent with the
/// ring / silent switch on silent, and the app's audio session (a video
/// playing) left as it is.
enum Sound {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "ding" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let wav = call.arguments as? FlutterStandardTypedData else {
      result(FlutterError(code: "failed", message: "ding takes the WAV's bytes", details: nil))
      return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ding.wav")
    do {
      try wav.data.write(to: url, options: .atomic)
    } catch {
      result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      return
    }
    var id: SystemSoundID = 0
    let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
    guard status == kAudioServicesNoError else {
      result(FlutterError(code: "failed", message: "System sound error \(status)", details: nil))
      return
    }
    AudioServicesPlaySystemSoundWithCompletion(id) { AudioServicesDisposeSystemSoundID(id) }
    result(nil)
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

/// Renders an edit's plan (lib/capture/render_plan.dart; method channel
/// `tabcam/video_edit`, method `render`, the plan's `toChannel`): `input`
/// and `output` paths, `video` (false for the sound alone, an `.m4a`), the
/// part kept (`startMs`–`endMs`), the video's own sound (`own`: `volume`, 0
/// to 1; left out: removed) and the song lane (`song`: `path`, `volume` and
/// `clips`, each `atMs` in the output, the song from `fromMs` to `toMs`, at
/// `speed`, 1 for now). With a `job`, `progress` calls back with `job` and
/// `done` (0 to 1) every quarter of a second while it renders. Replies with
/// the output path.
enum VideoEdit {
  static func handle(
    _ call: FlutterMethodCall, result: @escaping FlutterResult, channel: FlutterMethodChannel?
  ) {
    guard call.method == "render" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let reply: (Any?) -> Void = { value in
      DispatchQueue.main.async { result(value) }
    }
    guard let args = call.arguments as? [String: Any],
      let plan = VideoEditor.Plan(args: args)
    else {
      reply(FlutterError(code: "failed", message: "Bad arguments for render.", details: nil))
      return
    }
    var progress: ((Float) -> Void)?
    if let job = (args["job"] as? NSNumber)?.intValue {
      progress = { done in
        DispatchQueue.main.async {
          channel?.invokeMethod("progress", arguments: ["job": job, "done": Double(done)])
        }
      }
    }
    VideoEditor.render(plan, progress: progress) { error in
      if let error = error {
        reply(FlutterError(code: "failed", message: error, details: nil))
      } else {
        reply(plan.output.path)
      }
    }
  }
}

/// The AVFoundation side of `render`, free of Flutter and UIKit (the
/// RunnerTests smoke test calls it): an `AVMutableComposition` of the kept
/// part of the video (its orientation kept as the track's transform), its
/// own sound cut the same when kept, and the song lane's clips inserted on
/// one track where they start, with their volumes through an audio mix;
/// exported as H.264 and AAC in MP4, or, without the video, the sound alone
/// as AAC in M4A.
enum VideoEditor {
  /// A piece of the song lane: from `atMs` in the output, the song from
  /// `fromMs` to `toMs`.
  struct Clip: Equatable {
    let atMs: Int64
    let fromMs: Int64
    let toMs: Int64
    var speed: Double = 1
  }

  /// The song lane: its file, its volume, and its clips in output order.
  struct Song {
    let url: URL
    var volume: Float = 1
    let clips: [Clip]
  }

  /// What `render` is asked.
  struct Plan {
    let input: URL
    let output: URL
    var video: Bool = true
    let startMs: Int64
    let endMs: Int64
    /// The video's own sound's volume; nil: removed.
    var ownVolume: Float? = 1
    var song: Song?

    /// The plan the channel's arguments describe; nil when they're bad.
    init?(args: [String: Any]) {
      func int64(_ map: [String: Any], _ key: String) -> Int64? {
        (map[key] as? NSNumber)?.int64Value
      }
      func volume(_ map: [String: Any]) -> Float {
        let v = (map["volume"] as? NSNumber)?.floatValue ?? 1
        return v.isNaN ? 1 : min(max(v, 0), 1)
      }
      guard let input = args["input"] as? String,
        let output = args["output"] as? String,
        let startMs = int64(args, "startMs"),
        let endMs = int64(args, "endMs")
      else { return nil }
      var song: Song?
      if let lane = args["song"] as? [String: Any] {
        guard let path = lane["path"] as? String else { return nil }
        var clips: [Clip] = []
        for case let clip as [String: Any] in (lane["clips"] as? [Any]) ?? [] {
          guard let atMs = int64(clip, "atMs"), let fromMs = int64(clip, "fromMs"),
            let toMs = int64(clip, "toMs")
          else { return nil }
          clips.append(
            Clip(
              atMs: atMs, fromMs: fromMs, toMs: toMs,
              speed: (clip["speed"] as? NSNumber)?.doubleValue ?? 1))
        }
        song = Song(url: URL(fileURLWithPath: path), volume: volume(lane), clips: clips)
      }
      self.init(
        input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output),
        video: args["video"] as? Bool ?? true, startMs: startMs, endMs: endMs,
        ownVolume: (args["own"] as? [String: Any]).map { volume($0) }, song: song)
    }

    init(
      input: URL, output: URL, video: Bool = true, startMs: Int64, endMs: Int64,
      ownVolume: Float? = 1, song: Song? = nil
    ) {
      self.input = input
      self.output = output
      self.video = video
      self.startMs = startMs
      self.endMs = endMs
      self.ownVolume = ownVolume
      self.song = song
    }
  }

  /// Calls `completion` exactly once, on any thread, with nil on success or
  /// an error message; `progress`, every quarter of a second while it
  /// exports, with how much is done (0 to 1), on any thread.
  static func render(
    _ plan: Plan, progress: ((Float) -> Void)? = nil,
    completion: @escaping (String?) -> Void
  ) {
    Task {
      do {
        try await run(plan, progress: progress)
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

  private static func ms(_ value: Int64) -> CMTime { CMTime(value: value, timescale: 1000) }

  private static func run(_ plan: Plan, progress: ((Float) -> Void)?) async throws {
    let asset = AVURLAsset(url: plan.input)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      throw Failure("The video has no video track.")
    }
    let (trackRange, transform) = try await videoTrack.load(.timeRange, .preferredTransform)
    let wanted = CMTimeRange(start: ms(plan.startMs), end: ms(plan.endMs))
    let range = CMTimeRangeGetIntersection(wanted, otherRange: trackRange)
    guard range.duration > .zero else { throw Failure("Nothing to keep.") }
    if let song = plan.song, song.clips.contains(where: { $0.speed != 1 }) {
      throw Failure("A song at another speed can't be rendered yet.")
    }

    let composition = AVMutableComposition()
    // The volumes that aren't 1, one per audio track.
    var volumes: [AVMutableAudioMixInputParameters] = []
    func mix(_ track: AVMutableCompositionTrack, at volume: Float) {
      guard volume != 1 else { return }
      let parameters = AVMutableAudioMixInputParameters(track: track)
      parameters.setVolume(volume, at: .zero)
      volumes.append(parameters)
    }
    if plan.video {
      guard
        let compVideo = composition.addMutableTrack(
          withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { throw Failure("Could not add the video track.") }
      try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
      compVideo.preferredTransform = transform
    }

    if let ownVolume = plan.ownVolume {
      for audio in try await asset.loadTracks(withMediaType: .audio) {
        let audioRange = CMTimeRangeGetIntersection(
          try await audio.load(.timeRange), otherRange: range)
        guard audioRange.duration > .zero,
          let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { continue }
        try compAudio.insertTimeRange(audioRange, of: audio, at: audioRange.start - range.start)
        mix(compAudio, at: ownVolume)
      }
    }

    // No clip of the song falls in the kept part: silence.
    // The song's asset, held until the export is done (as the video's
    // is): a composition doesn't keep the assets of the tracks it was made
    // from, and one let go fails the export.
    var songAsset: AVURLAsset?
    if let song = plan.song, !song.clips.isEmpty {
      let asset = AVURLAsset(url: song.url)
      songAsset = asset
      guard let audio = try await asset.loadTracks(withMediaType: .audio).first
      else { throw Failure("The song has no sound.") }
      let audioRange = try await audio.load(.timeRange)
      guard
        let compAudio = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { throw Failure("Could not add the song's track.") }
      for clip in song.clips where clip.toMs > clip.fromMs && clip.fromMs >= 0 && clip.atMs >= 0 {
        let from = CMTimeMinimum(ms(clip.fromMs), audioRange.duration)
        let to = CMTimeMinimum(ms(clip.toMs), audioRange.duration)
        guard to > from else { continue }
        try compAudio.insertTimeRange(
          CMTimeRange(start: audioRange.start + from, end: audioRange.start + to), of: audio,
          at: ms(clip.atMs))
      }
      mix(compAudio, at: song.volume)
    }

    if FileManager.default.fileExists(atPath: plan.output.path) {
      try FileManager.default.removeItem(at: plan.output)
    }
    if !plan.video && !composition.tracks.contains(where: { $0.mediaType == .audio }) {
      throw Failure("There is no sound in the kept part.")
    }
    guard
      let export = AVAssetExportSession(
        asset: composition,
        presetName: plan.video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A)
    else { throw Failure("Could not start the export.") }
    export.outputURL = plan.output
    export.outputFileType = plan.video ? .mp4 : .m4a
    if !volumes.isEmpty {
      let audioMix = AVMutableAudioMix()
      audioMix.inputParameters = volumes
      export.audioMix = audioMix
    }
    export.shouldOptimizeForNetworkUse = true
    let polling = progress.map { report in
      Task {
        while !Task.isCancelled {
          report(export.progress)
          try? await Task.sleep(nanoseconds: 250_000_000)
        }
      }
    }
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      export.exportAsynchronously { done.resume() }
    }
    polling?.cancel()
    withExtendedLifetime((asset, songAsset)) {}
    guard export.status == .completed else {
      throw Failure(export.error?.localizedDescription ?? "The export did not complete.")
    }
    progress?(1)
  }
}
