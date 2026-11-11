import AVFoundation
import Flutter
import UIKit
import XCTest

@testable import Runner

/// A smoke test of the video editor's renderer (`VideoEditor.render`, the
/// `render` method of `tabcam/video_edit`): a 2 s made-up clip (a colour
/// that changes, no sound) and a made-up tone as the song, rendered on the
/// simulator as the app's plans are.
class RunnerTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  func testRendersAPlanWithItsSongAndProgress() async throws {
    let video = dir.appendingPathComponent("riff.mp4")
    try await makeVideo(video, seconds: 2)
    let song = dir.appendingPathComponent("tone.wav")
    try makeTone(song, seconds: 2)

    // Kept from 0.5 s to 1.5 s, the song's first 0.8 s coming in 0.2 s
    // after the kept part's start, at half its volume.
    let output = dir.appendingPathComponent("out.mp4")
    let plan = VideoEditor.Plan(
      input: video, output: output, startMs: 500, endMs: 1500, ownVolume: 1,
      song: VideoEditor.Song(
        url: song, volume: 0.5, clips: [VideoEditor.Clip(atMs: 200, fromMs: 0, toMs: 800)]))
    let progress = Progress()
    let error = await render(plan, progress: progress)
    XCTAssertNil(error)
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 1, accuracy: 0.15)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(videoTracks.count, 1)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    XCTAssertEqual(audioTracks.count, 1)
    XCTAssertEqual(progress.last, 1)

    // The sound alone: an M4A of the song where it plays.
    let sound = dir.appendingPathComponent("out.m4a")
    let soundPlan = VideoEditor.Plan(
      input: video, output: sound, video: false, startMs: 500, endMs: 1500, ownVolume: nil,
      song: VideoEditor.Song(
        url: song, clips: [VideoEditor.Clip(atMs: 200, fromMs: 0, toMs: 800)]))
    let soundError = await render(soundPlan, progress: nil)
    XCTAssertNil(soundError)
    let soundAsset = AVURLAsset(url: sound)
    let soundTracks = try await soundAsset.loadTracks(withMediaType: .audio)
    XCTAssertEqual(soundTracks.count, 1)
    let videoInSound = try await soundAsset.loadTracks(withMediaType: .video)
    XCTAssertTrue(videoInSound.isEmpty)
    let soundDuration = try await soundAsset.load(.duration)
    XCTAssertEqual(soundDuration.seconds, 1, accuracy: 0.15)

    // No sound at all, and no picture: nothing to make.
    let nothing = VideoEditor.Plan(
      input: video, output: dir.appendingPathComponent("none.m4a"), video: false, startMs: 0,
      endMs: 1000, ownVolume: nil)
    let nothingError = await render(nothing, progress: nil)
    XCTAssertNotNil(nothingError)
  }

  func testDrawsTheLayersWhileTheyShow() async throws {
    let video = dir.appendingPathComponent("riff.mp4")
    try await makeVideo(video, seconds: 2)
    // A red band along the bottom for the kept part's first half second,
    // and a red square at the top left, 20% of the short side, 5% in.
    let output = dir.appendingPathComponent("layers.mp4")
    let plan = VideoEditor.Plan(
      input: video, output: output, startMs: 500, endMs: 1500, ownVolume: nil,
      layers: [
        VideoEditor.Layer(id: "tab", image: 0, anchor: .bottomFull, fromMs: 0, toMs: 500),
        VideoEditor.Layer(
          id: "title", image: 1, anchor: .topLeft, heightU: 0.2, marginU: 0.05),
      ],
      images: [try red(64, 16), try red(32, 32)])
    let error = await render(plan, progress: nil)
    XCTAssertNil(error)
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 1, accuracy: 0.15)
    // 160 x 120: the band at the bottom while it shows, not after; the
    // square 6 + 12 px in.
    XCTAssertTrue(try isRed(asset, at: 0.25, x: 80, y: 118))
    XCTAssertFalse(try isRed(asset, at: 0.8, x: 80, y: 118))
    XCTAssertTrue(try isRed(asset, at: 0.6, x: 18, y: 18))
  }

  func testPlacesLayersAsTheAppDoes() {
    let frame = CGSize(width: 1920, height: 1080)
    let band = VideoEditor.Layer(image: 0, anchor: .bottomFull)
    XCTAssertEqual(
      band.rect(in: frame, image: CGSize(width: 1280, height: 240)),
      CGRect(x: 0, y: 720, width: 1920, height: 360))
    // Of the short side (1024): half high, a quarter in, an eighth higher.
    let mark = VideoEditor.Layer(
      image: 0, anchor: .bottomRight, heightU: 0.5, marginU: 0.25, liftU: 0.125)
    XCTAssertEqual(
      mark.rect(in: CGSize(width: 1920, height: 1024), image: CGSize(width: 400, height: 200)),
      CGRect(x: 640, y: 128, width: 1024, height: 512))
    let plan = VideoEditor.Plan(args: [
      "input": "/tmp/in.mp4", "output": "/tmp/out.mp4", "startMs": 0, "endMs": 1000,
      "images": [FlutterStandardTypedData(bytes: Data([1, 2, 3]))],
      "layers": [
        [
          "id": "tab", "image": 0, "anchor": "bottomFull", "fromMs": 0, "toMs": 500,
          "fadeInMs": 0, "opacity": 1,
        ]
      ],
    ])
    XCTAssertEqual(
      plan?.layers, [VideoEditor.Layer(id: "tab", image: 0, anchor: .bottomFull, toMs: 500)])
    XCTAssertNil(
      VideoEditor.Plan(args: [
        "input": "/tmp/in.mp4", "output": "/tmp/out.mp4", "startMs": 0, "endMs": 1000,
        "layers": [["image": 0, "anchor": "bottomFull"]],
      ]))
  }

  /// A red PNG, `width` x `height`.
  private func red(_ width: Int, _ height: Int) throws -> Data {
    let size = CGSize(width: width, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
    return try XCTUnwrap(image.pngData())
  }

  /// Whether `asset`'s frame at `seconds` is red at (`x`, `y`), from its top
  /// left.
  private func isRed(_ asset: AVAsset, at seconds: Double, x: Int, y: Int) throws -> Bool {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let image = try generator.copyCGImage(
      at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(
      image,
      in: CGRect(
        x: -CGFloat(x), y: -CGFloat(image.height - 1 - y), width: CGFloat(image.width),
        height: CGFloat(image.height)))
    return pixel[0] > 180 && pixel[1] < 90 && pixel[2] < 90
  }

  func testReadsTheChannelsArguments() {
    let plan = VideoEditor.Plan(args: [
      "input": "/tmp/in.mp4", "output": "/tmp/out.mp4", "video": true, "startMs": 500,
      "endMs": 1500, "own": ["volume": 0.5],
      "song": [
        "path": "/tmp/song.m4a", "volume": 2,
        "clips": [["atMs": 200, "fromMs": 0, "toMs": 800, "speed": 1]],
      ],
    ])
    XCTAssertEqual(plan?.startMs, 500)
    XCTAssertEqual(plan?.ownVolume, 0.5)
    XCTAssertEqual(plan?.song?.volume, 1)
    XCTAssertEqual(plan?.song?.clips, [VideoEditor.Clip(atMs: 200, fromMs: 0, toMs: 800)])
    let silent = VideoEditor.Plan(args: [
      "input": "/tmp/in.mp4", "output": "/tmp/out.mp4", "startMs": 0, "endMs": 1000,
    ])
    XCTAssertNotNil(silent)
    XCTAssertNil(silent?.ownVolume)
    XCTAssertNil(silent?.song)
    XCTAssertNil(VideoEditor.Plan(args: ["input": "/tmp/in.mp4"]))
  }

  /// The progress reported, in order.
  private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Float] = []
    func add(_ value: Float) {
      lock.lock()
      values.append(value)
      lock.unlock()
    }
    var last: Float? {
      lock.lock()
      defer { lock.unlock() }
      return values.last
    }
  }

  private func render(_ plan: VideoEditor.Plan, progress: Progress?) async -> String? {
    await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
      VideoEditor.render(plan, progress: progress.map { p in { p.add($0) } }) { error in
        done.resume(returning: error)
      }
    }
  }

  /// A silent H.264 video, 160×120 at 30 frames a second, its colour
  /// changing.
  private func makeVideo(_ url: URL, seconds: Int) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120,
      ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120,
      ])
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(seconds * 30) {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
      let pixels = try XCTUnwrap(buffer)
      CVPixelBufferLockBaseAddress(pixels, [])
      memset(
        CVPixelBufferGetBaseAddress(pixels), Int32(frame * 4 % 256),
        CVPixelBufferGetDataSize(pixels))
      CVPixelBufferUnlockBaseAddress(pixels, [])
      XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed)
  }

  /// A 440 Hz tone, mono, at 44.1 kHz, as a WAV.
  private func makeTone(_ url: URL, seconds: Int) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(44100 * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frames) {
      samples[i] = 0.5 * sin(2 * .pi * 440 * Float(i) / 44100)
    }
    try file.write(from: buffer)
  }
}
