import AVFoundation
import AudioToolbox
import Flutter
import ImageIO
import QuartzCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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

/// Renders an edit's plan (lib/capture/render_plan.dart; method channel
/// `tabcam/video_edit`, method `render`, the plan's `toChannel`): `input`
/// and `output` paths, `video` (false for the sound alone, an `.m4a`), the
/// part kept (`startMs`–`endMs`), the video's own sound (`own`: `volume`, 0
/// to 1; left out: removed) and the song lane (`song`: `path`, `volume` and
/// `clips`, each `atMs` in the output, the song from `fromMs` to `toMs`, at
/// `speed`, 1 for now), and what's drawn over the picture: `images` (PNGs)
/// and `layers` (each its `image`'s index, `anchor`, `heightU`, `marginU`,
/// `liftU`, `liftW`, `fromMs`, `toMs`, `fadeInMs` and `opacity`), and the
/// fades (`fadeInMs`, `fadeOutMs`; left out: none): the picture, with its
/// layers, from and to black, and the sound with it. With a `job`,
/// `progress` calls back with `job` and `done` (0 to 1) every quarter of a
/// second while it renders. Replies with the output path.
///
/// Also, for Cam's takes (lib/capture/take_h264.dart, `TakeH264`):
/// `codec` (`input`) replies with the four letters of the video's codec
/// (`avc1` for H.264, `hvc1` for HEVC; nil without a video track), and
/// `h264` (`input`, `output`) makes the whole video H.264, its sound kept,
/// replying with the output path.
enum VideoEdit {
  static func handle(
    _ call: FlutterMethodCall, result: @escaping FlutterResult, channel: FlutterMethodChannel?
  ) {
    let reply: (Any?) -> Void = { value in
      DispatchQueue.main.async { result(value) }
    }
    switch call.method {
    case "render": break
    case "codec", "h264":
      TakeH264.handle(call, reply: reply)
      return
    default:
      result(FlutterMethodNotImplemented)
      return
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

/// Cam's takes on iOS, made H.264 where the camera wrote another codec
/// (camera_avfoundation writes the codec the device recommends, which can
/// be HEVC: Chrome and Firefox don't play that everywhere). `codec` tells
/// the take's video codec; `h264` exports the whole take through
/// `VideoEditor.render` with nothing drawn on it: the highest quality
/// preset writes H.264 (HEVC has presets of its own), the sound as AAC,
/// the picture with its orientation kept.
enum TakeH264 {
  static func handle(_ call: FlutterMethodCall, reply: @escaping (Any?) -> Void) {
    guard let args = call.arguments as? [String: Any],
      let input = args["input"] as? String
    else {
      reply(FlutterError(code: "failed", message: "Bad arguments for \(call.method).", details: nil))
      return
    }
    let url = URL(fileURLWithPath: input)
    if call.method == "codec" {
      Task {
        do {
          reply(try await codec(of: url))
        } catch {
          reply(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        }
      }
      return
    }
    guard let output = args["output"] as? String else {
      reply(FlutterError(code: "failed", message: "Bad arguments for h264.", details: nil))
      return
    }
    convert(input: url, output: URL(fileURLWithPath: output)) { error in
      if let error = error {
        reply(FlutterError(code: "failed", message: error, details: nil))
      } else {
        reply(output)
      }
    }
  }

  /// The four letters of the video track's codec (`avc1`, `hvc1`…); nil
  /// without a video track.
  static func codec(of url: URL) async throws -> String? {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first,
      let format = try await track.load(.formatDescriptions).first
    else { return nil }
    return fourCC(CMFormatDescriptionGetMediaSubType(format))
  }

  static func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(decoding: bytes, as: UTF8.self)
  }

  /// Calls `completion` exactly once, on any thread, with nil on success or
  /// an error message.
  static func convert(input: URL, output: URL, completion: @escaping (String?) -> Void) {
    Task {
      do {
        let duration = try await AVURLAsset(url: input).load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else {
          completion("The take is empty.")
          return
        }
        let plan = VideoEditor.Plan(
          input: input, output: output, startMs: 0,
          endMs: Int64((duration.seconds * 1000).rounded(.up)))
        VideoEditor.render(plan, completion: completion)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }
}

/// The AVFoundation side of `render`, free of Flutter and UIKit (the
/// RunnerTests smoke test calls it): an `AVMutableComposition` of the kept
/// part of the video (its orientation kept as the track's transform), its
/// own sound cut the same when kept, and the song lane's clips inserted on
/// one track where they start, with their volumes through an audio mix;
/// the layers (with the picture) through a video composition, one Core
/// Animation layer each, shown and faded by opacity animations; the fades
/// a black layer over them all, its opacity animated from 1 to 0 and back
/// (`fadeKeyframes`), and volume ramps on each audio track (`fade`, every
/// track's the same: the mix fades); exported as
/// H.264 and AAC in MP4, or, without the video, the sound alone as AAC in
/// M4A.
enum VideoEditor {
  /// A piece of the song lane: from `atMs` in the output, the song from
  /// `fromMs` to `toMs`.
  struct Clip: Equatable {
    let atMs: Int64
    let fromMs: Int64
    let toMs: Int64
    var speed: Double = 1
  }

  /// Where a layer sits (lib/capture/render_plan.dart, `LayerAnchor`).
  enum Anchor: String {
    case topLeft, bottomRight, bottomFull
  }

  /// Something drawn over the picture (`PlanLayer`): the plan's `image`th
  /// image, placed by `anchor` (`heightU` high, `marginU` in from the
  /// corner and `liftU` higher, as fractions of the frame's short side, and
  /// `liftW` higher still, as a fraction of its width, above the tab's
  /// tallest band; a bottom band as wide as the frame), from `fromMs` to
  /// `toMs` (nil: the end) in the output, fading in over `fadeInMs` to
  /// `opacity`.
  struct Layer: Equatable {
    var id = ""
    let image: Int
    let anchor: Anchor
    var heightU: CGFloat = 0
    var marginU: CGFloat = 0
    var liftU: CGFloat = 0
    var liftW: CGFloat = 0
    var fromMs: Int64 = 0
    var toMs: Int64?
    var fadeInMs: Int64 = 0
    var opacity: Float = 1

    /// Where it's drawn on a `frame` (upright, its origin at the top left),
    /// an `image` that size scaled into it: as `PlanLayer.rectIn` places it.
    func rect(in frame: CGSize, image: CGSize) -> CGRect {
      guard image.width > 0, image.height > 0 else { return .zero }
      let short = min(frame.width, frame.height)
      if anchor == .bottomFull {
        let height = frame.width * image.height / image.width
        return CGRect(x: 0, y: frame.height - height, width: frame.width, height: height)
      }
      let height = heightU * short
      let width = height * image.width / image.height
      let margin = marginU * short
      if anchor == .topLeft {
        return CGRect(x: margin, y: margin, width: width, height: height)
      }
      return CGRect(
        x: frame.width - margin - width,
        y: frame.height - margin - liftU * short - liftW * frame.width - height,
        width: width, height: height)
    }
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
    /// What's drawn over the picture, each naming one of `images` (PNGs).
    var layers: [Layer] = []
    var images: [Data] = []
    /// How long the output fades in from black and silence, and out to
    /// them (0: none; the app keeps each at most half the kept part).
    var fadeInMs: Int64 = 0
    var fadeOutMs: Int64 = 0

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
      var images: [Data] = []
      for image in (args["images"] as? [Any]) ?? [] {
        guard let png = image as? FlutterStandardTypedData else { return nil }
        images.append(png.data)
      }
      var layers: [Layer] = []
      for case let layer as [String: Any] in (args["layers"] as? [Any]) ?? [] {
        func number(_ key: String) -> CGFloat {
          CGFloat((layer[key] as? NSNumber)?.doubleValue ?? 0)
        }
        guard let image = (layer["image"] as? NSNumber)?.intValue, images.indices.contains(image),
          let anchor = (layer["anchor"] as? String).flatMap(Anchor.init(rawValue:))
        else { return nil }
        layers.append(
          Layer(
            id: layer["id"] as? String ?? "", image: image, anchor: anchor,
            heightU: number("heightU"), marginU: number("marginU"), liftU: number("liftU"),
            liftW: number("liftW"),
            fromMs: int64(layer, "fromMs") ?? 0, toMs: int64(layer, "toMs"),
            fadeInMs: int64(layer, "fadeInMs") ?? 0,
            opacity: min(max((layer["opacity"] as? NSNumber)?.floatValue ?? 1, 0), 1)))
      }
      self.init(
        input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output),
        video: args["video"] as? Bool ?? true, startMs: startMs, endMs: endMs,
        ownVolume: (args["own"] as? [String: Any]).map { volume($0) }, song: song,
        layers: layers, images: images,
        fadeInMs: max(0, int64(args, "fadeInMs") ?? 0),
        fadeOutMs: max(0, int64(args, "fadeOutMs") ?? 0))
    }

    init(
      input: URL, output: URL, video: Bool = true, startMs: Int64, endMs: Int64,
      ownVolume: Float? = 1, song: Song? = nil, layers: [Layer] = [], images: [Data] = [],
      fadeInMs: Int64 = 0, fadeOutMs: Int64 = 0
    ) {
      self.input = input
      self.output = output
      self.video = video
      self.startMs = startMs
      self.endMs = endMs
      self.ownVolume = ownVolume
      self.song = song
      self.layers = layers
      self.images = images
      self.fadeInMs = fadeInMs
      self.fadeOutMs = fadeOutMs
    }

    /// Whether it fades in or out.
    var fades: Bool { fadeInMs > 0 || fadeOutMs > 0 }
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
    // The volumes that aren't 1 throughout, one per audio track: its lane's,
    // and the fades.
    var volumes: [AVMutableAudioMixInputParameters] = []
    func mix(_ track: AVMutableCompositionTrack, at volume: Float) {
      guard volume != 1 || plan.fades else { return }
      let parameters = AVMutableAudioMixInputParameters(track: track)
      fade(
        parameters, volume: volume, fadeInMs: plan.fadeInMs, fadeOutMs: plan.fadeOutMs,
        length: range.duration)
      volumes.append(parameters)
    }
    var videoComposition: AVMutableVideoComposition?
    if plan.video {
      guard
        let compVideo = composition.addMutableTrack(
          withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { throw Failure("Could not add the video track.") }
      try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
      if plan.layers.isEmpty && !plan.fades {
        compVideo.preferredTransform = transform
      } else {
        // The video composition turns it upright instead.
        let (naturalSize, frameRate) = try await videoTrack.load(.naturalSize, .nominalFrameRate)
        videoComposition = try layered(
          compVideo, naturalSize: naturalSize, transform: transform, frameRate: frameRate,
          duration: range.duration, layers: plan.layers, images: plan.images,
          fadeInMs: plan.fadeInMs, fadeOutMs: plan.fadeOutMs)
      }
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
      // With the picture, each clip is cut to the video's kept part
      // (`range`), as the take's own sound is: the editor's end can pass
      // the video track's end (the player's duration is the longest
      // track's), and a song running past the video makes the composition
      // outlast its video composition's instruction, which the export
      // rejects (-11841, "could not be composed").
      let end: CMTime? = plan.video ? range.duration : nil
      for clip in song.clips where clip.toMs > clip.fromMs && clip.fromMs >= 0 && clip.atMs >= 0 {
        let at = ms(clip.atMs)
        if let end, at >= end { continue }
        let from = CMTimeMinimum(ms(clip.fromMs), audioRange.duration)
        var to = CMTimeMinimum(ms(clip.toMs), audioRange.duration)
        if let end { to = CMTimeMinimum(to, from + (end - at)) }
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
    export.videoComposition = videoComposition
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

  /// A video composition of `track` (the video's kept part, from 0,
  /// `duration` long) turned upright (`transform`, as its frames show), with
  /// `layers` (their `images`) over it: each a Core Animation layer where
  /// its anchor puts it, its opacity 0 outside its time, rising to its
  /// opacity over its fade, as `PlanLayer.alphaAt` says; and over them all,
  /// with fades, a black layer, opaque at the start and the end, clear in
  /// between (`fadeKeyframes`).
  static func layered(
    _ track: AVMutableCompositionTrack, naturalSize: CGSize, transform: CGAffineTransform,
    frameRate: Float, duration: CMTime, layers: [Layer], images: [Data],
    fadeInMs: Int64 = 0, fadeOutMs: Int64 = 0
  ) throws -> AVMutableVideoComposition {
    // The frame as displayed: the transform rotates (and maybe mirrors) the
    // natural frame; its bounding box is moved back to the origin.
    let shown = CGRect(origin: .zero, size: naturalSize).applying(transform)
    let renderSize = CGSize(width: evenRound(shown.width), height: evenRound(shown.height))
    let layerTransform = transform.concatenating(
      CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layerInstruction.setTransform(layerTransform, at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layerInstruction]
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    let fps = frameRate > 0 ? frameRate : 30
    videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
    videoComposition.instructions = [instruction]

    var pictures: [CGImage] = []
    for png in images {
      guard let source = CGImageSourceCreateWithData(png as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0
      else { throw Failure("A layer's image is not a valid PNG.") }
      pictures.append(image)
    }
    // Core Animation in a video composition has its origin at the bottom
    // left, so y = 0 is the bottom of the frame.
    let frame = CGRect(origin: .zero, size: renderSize)
    let parent = CALayer()
    parent.frame = frame
    let videoLayer = CALayer()
    videoLayer.frame = frame
    parent.addSublayer(videoLayer)
    let total = duration.seconds
    for layer in layers {
      let start = max(0, Double(layer.fromMs) / 1000)
      let end = min(total, layer.toMs.map { Double($0) / 1000 } ?? total)
      guard end > start else { continue }
      let image = pictures[layer.image]
      let box = layer.rect(
        in: renderSize, image: CGSize(width: image.width, height: image.height))
      let shape = CALayer()
      shape.frame = CGRect(
        x: box.minX, y: renderSize.height - box.maxY, width: box.width, height: box.height)
      shape.contents = image
      shape.contentsGravity = .resize
      shape.opacity = 0
      // Outside each animation's time it has no effect: opacity stays 0.
      let fade = min(Double(layer.fadeInMs) / 1000, end - start)
      if fade > 0 {
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = layer.opacity
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + start
        fadeIn.duration = fade
        fadeIn.isRemovedOnCompletion = false
        fadeIn.fillMode = .removed
        shape.add(fadeIn, forKey: "fade")
      }
      if end - start > fade {
        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = layer.opacity
        show.toValue = layer.opacity
        show.beginTime = AVCoreAnimationBeginTimeAtZero + start + fade
        show.duration = end - start - fade
        show.isRemovedOnCompletion = false
        show.fillMode = .removed
        shape.add(show, forKey: "show")
      }
      parent.addSublayer(shape)
    }
    if let keyframes = fadeKeyframes(
      fadeIn: Double(fadeInMs) / 1000, fadeOut: Double(fadeOutMs) / 1000, total: total)
    {
      let black = CALayer()
      black.frame = frame
      black.backgroundColor = CGColor(gray: 0, alpha: 1)
      black.opacity = 0
      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = keyframes.0
      fade.keyTimes = keyframes.1
      fade.calculationMode = .linear
      fade.beginTime = AVCoreAnimationBeginTimeAtZero
      fade.duration = total
      fade.isRemovedOnCompletion = false
      fade.fillMode = .both
      black.add(fade, forKey: "fade")
      parent.addSublayer(black)
    }
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer, in: parent)
    return videoComposition
  }

  /// The black's opacity over an output `total` seconds long, as a
  /// keyframe animation's values and key times (fractions of `total`): 1
  /// at the start, 0 after `fadeIn`, 0 again `fadeOut` before the end, 1
  /// at the end, straight lines between (each fade at most half the
  /// output, as `Fades.levelAt` in Dart has them). Nil without a fade.
  static func fadeKeyframes(fadeIn: Double, fadeOut: Double, total: Double)
    -> ([Float], [NSNumber])?
  {
    guard total > 0 else { return nil }
    let fadeIn = min(max(0, fadeIn), total / 2)
    let fadeOut = min(max(0, fadeOut), total / 2)
    guard fadeIn > 0 || fadeOut > 0 else { return nil }
    var values: [Float] = []
    var times: [Double] = []
    if fadeIn > 0 {
      values += [1, 0]
      times += [0, fadeIn]
    } else {
      values.append(0)
      times.append(0)
    }
    if fadeOut > 0 {
      values += [0, 1]
      times += [total - fadeOut, total]
    } else {
      values.append(0)
      times.append(total)
    }
    return (values, times.map { NSNumber(value: $0 / total) })
  }

  /// A track's `volume` in the mix, faded in from silence over its first
  /// `fadeInMs` and out to it over its last `fadeOutMs` of `length`
  /// (straight ramps, each at most half of it; between them, the volume).
  static func fade(
    _ parameters: AVMutableAudioMixInputParameters, volume: Float, fadeInMs: Int64,
    fadeOutMs: Int64, length: CMTime
  ) {
    let half = CMTimeMultiplyByRatio(length, multiplier: 1, divisor: 2)
    let fadeIn = CMTimeMinimum(ms(max(0, fadeInMs)), half)
    let fadeOut = CMTimeMinimum(ms(max(0, fadeOutMs)), half)
    if fadeIn > .zero {
      parameters.setVolumeRamp(
        fromStartVolume: 0, toEndVolume: volume,
        timeRange: CMTimeRange(start: .zero, duration: fadeIn))
    } else {
      parameters.setVolume(volume, at: .zero)
    }
    if fadeOut > .zero {
      parameters.setVolumeRamp(
        fromStartVolume: volume, toEndVolume: 0,
        timeRange: CMTimeRange(start: length - fadeOut, duration: fadeOut))
    }
  }

  /// Rounds a render dimension to an even number of pixels, as H.264 wants.
  private static func evenRound(_ value: CGFloat) -> CGFloat {
    let rounded = Int(abs(value).rounded())
    return CGFloat(max(2, rounded + rounded % 2))
  }
}
