import CoreGraphics
import CoreML
import Foundation

// GeoCalib on device: preprocessing (Swift) → network (Core ML) → LM optimizer (Swift).
// Model: cvg/GeoCalib (Veicht et al., ECCV 2024). Code Apache-2.0, weights CC BY 4.0.
// Network converted to Core ML in "Claude outputs/geocalib-coreml" (export_coreml.py).

/// Which converted GeoCalib network to run.
nonisolated enum GeoCalibMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    /// fp16 network, 57 MB. Set A on Mac: up to ~0.7° pitch / 1.5 % focal from Heavy.
    case light
    /// fp32 network, 114 MB. Set A on Mac: identical to the original PyTorch GeoCalib.
    case heavy

    var id: String { rawValue }
    /// Compiled model name in the app bundle (Xcode compiles the .mlpackage into .mlmodelc).
    var resourceName: String { self == .light ? "GeoCalibNet_fp16" : "GeoCalibNet_fp32" }
}

/// One GeoCalib run: the estimate plus where the time went.
nonisolated struct GeoCalibRun: Sendable {
    let mode: GeoCalibMode
    let result: GeoCalibResult
    let preprocessMs: Double
    let predictMs: Double
    let optimizeMs: Double
    var totalMs: Double { preprocessMs + predictMs + optimizeMs }
}

nonisolated final class GeoCalibEstimator: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case modelNotFound(String), missingOutput(String), unsupportedOutputType, unexpectedOutputSize(String)

        var description: String {
            switch self {
            case .modelNotFound(let name):
                return "\(name).mlpackage is not in the app bundle (the fp32 model is git-ignored; copy it into Resource/MLModels)."
            case .missingOutput(let name): return "The GeoCalib model did not return \(name)."
            case .unsupportedOutputType: return "The GeoCalib model returned an unsupported number type."
            case .unexpectedOutputSize(let detail): return "The GeoCalib model returned outputs of the wrong size (\(detail))."
            }
        }
    }

    let mode: GeoCalibMode
    private let url: URL
    private let computeUnits: MLComputeUnits
    /// One compiled function per input size (h416_w320, h544_w320, …), loaded on first use.
    private var models: [String: MLModel] = [:]
    /// Serialises loading and prediction (photos are analysed two at a time).
    private let lock = NSLock()

    /// - Parameter computeUnits: CPU + GPU by default. The Neural Engine cannot compile the
    ///   backbone's large-kernel depthwise convolutions ("grouped conv with large kernel size").
    init(mode: GeoCalibMode, computeUnits: MLComputeUnits = .cpuAndGPU, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: mode.resourceName, withExtension: "mlmodelc") else {
            throw Failure.modelNotFound(mode.resourceName)
        }
        self.mode = mode
        self.url = url
        self.computeUnits = computeUnits
        _ = try model(width: 320, height: 416)   // fail early if the package cannot load
    }

    /// The fixed-shape function for this input size. Sizes come from `GeoCalibPreprocessor.supportedLongSides`.
    private func model(width: Int, height: Int) throws -> MLModel {
        let name = "h\(height)_w\(width)"
        lock.lock(); defer { lock.unlock() }
        if let m = models[name] { return m }
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        config.functionName = name
        let m = try MLModel(contentsOf: url, configuration: config)
        models[name] = m
        return m
    }

    /// Runs the network and the optimizer on an already preprocessed input.
    func estimate(_ input: GeoCalibInput, preprocessMs: Double = 0) throws -> GeoCalibRun {
        let w = input.width, h = input.height
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: h), NSNumber(value: w)], dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * h * w)
        let s = array.strides.map { $0.intValue }
        for ch in 0..<3 {
            for y in 0..<h {
                for x in 0..<w {
                    ptr[ch * s[1] + y * s[2] + x * s[3]] = input.pixels[(ch * h + y) * w + x]
                }
            }
        }

        let t1 = Date()
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: array)])
        let network = try model(width: w, height: h)
        lock.lock()
        let prediction = Result { try network.prediction(from: provider) }
        lock.unlock()
        let out = try prediction.get()
        let predictMs = Date().timeIntervalSince(t1) * 1000

        func read(_ name: String) throws -> [Float] {
            guard let a = out.featureValue(for: name)?.multiArrayValue else { throw Failure.missingOutput(name) }
            return try Self.floats(a)
        }
        let up = try read("up_field")                 // 1 x 2 x H x W
        let upConf = try read("up_confidence")        // 1 x H x W
        let lat = try read("latitude_field")          // 1 x 1 x H x W
        let latConf = try read("latitude_confidence") // 1 x H x W
        let n = h * w
        guard up.count == 2 * n, upConf.count == n, lat.count == n, latConf.count == n else {
            throw Failure.unexpectedOutputSize("got \(up.count)/\(upConf.count)/\(lat.count)/\(latConf.count) values for a \(w)x\(h) input")
        }

        let t2 = Date()
        let fields = GeoCalibFields(width: w, height: h,
                                    upX: Array(up[0..<n]), upY: Array(up[n..<(2 * n)]),
                                    upConfidence: upConf, latitude: lat, latitudeConfidence: latConf)
        let result = GeoCalibOptimizer.calibrate(fields, scaleX: input.scaleX, scaleY: input.scaleY,
                                                 cropPadX: input.cropPadX, cropPadY: input.cropPadY)
        let optimizeMs = Date().timeIntervalSince(t2) * 1000
        return GeoCalibRun(mode: mode, result: result, preprocessMs: preprocessMs,
                           predictMs: predictMs, optimizeMs: optimizeMs)
    }

    /// Copies any MLMultiArray (fp32 / fp16 / fp64, any strides) to a dense row-major [Float].
    static func floats(_ a: MLMultiArray) throws -> [Float] {
        let shape = a.shape.map { $0.intValue }
        let strides = a.strides.map { $0.intValue }
        let count = shape.reduce(1, *)
        var out = [Float](repeating: 0, count: count)
        var index = [Int](repeating: 0, count: shape.count)
        let maxOffset = zip(shape, strides).reduce(0) { $0 + ($1.0 - 1) * $1.1 }

        func offset() -> Int { zip(index, strides).reduce(0) { $0 + $1.0 * $1.1 } }
        func advance() {
            var d = shape.count - 1
            while d >= 0 {
                index[d] += 1
                if index[d] < shape[d] { return }
                index[d] = 0
                d -= 1
            }
        }

        switch a.dataType {
        case .float32:
            let p = a.dataPointer.bindMemory(to: Float.self, capacity: maxOffset + 1)
            for i in 0..<count { out[i] = p[offset()]; advance() }
        case .float16:
            let p = a.dataPointer.bindMemory(to: Float16.self, capacity: maxOffset + 1)
            for i in 0..<count { out[i] = Float(p[offset()]); advance() }
        case .double:
            let p = a.dataPointer.bindMemory(to: Double.self, capacity: maxOffset + 1)
            for i in 0..<count { out[i] = Float(p[offset()]); advance() }
        default:
            throw Failure.unsupportedOutputType
        }
        return out
    }
}

/// The GeoCalib network(s) a scan needs, loaded once per analysis run (like `AnalysisModels`) and released after.
/// A model that cannot load is reported per photo instead of failing the run.
nonisolated final class GeoCalibModels: @unchecked Sendable {
    let estimators: [GeoCalibMode: GeoCalibEstimator]
    let loadErrors: [GeoCalibMode: String]

    /// Time spent loading (and, on first launch, compiling) the models, ms.
    let loadMs: Double

    init(modes: [GeoCalibMode] = GeoCalibMode.allCases, bundle: Bundle = .main) {
        let t0 = Date()
        var loaded: [GeoCalibMode: GeoCalibEstimator] = [:]
        var errors: [GeoCalibMode: String] = [:]
        for mode in modes {
            do { loaded[mode] = try GeoCalibEstimator(mode: mode, bundle: bundle) }
            catch { errors[mode] = String(describing: error) }
        }
        estimators = loaded
        loadErrors = errors
        loadMs = Date().timeIntervalSince(t0) * 1000
    }
}
