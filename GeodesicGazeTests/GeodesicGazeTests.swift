//
//  GeodesicGazeTests.swift
//  GeodesicGazeTests
//
//  Created by Trevor Gravely on 9/1/24.
//

@testable import GeodesicGaze
import XCTest
import Metal
import simd

struct EllintResult {
    var val: Float
    var err: Float 
    var status: Int32
}

struct SchwarzschildLenseResult {
    var varphitilde: Float
    var ccw: Bool
    var status: Int32
}

struct KerrRadialRootsResult {
    var r1: simd_float2
    var r2: simd_float2
    var r3: simd_float2
    var r4: simd_float2
    var status: Int32
}

struct KerrLenseResult {
    var alpha: Float
    var beta: Float
    var eta: Float
    var lambda: Float
    var phif: Float
    var thetaf: Float
    var kerrLenseStatus: Int32
}

struct Result {
    var IrValue: Float
    var cosThetaObserverValue: Float
    var GphiValue: Float
    var mathcalGphisValue: Float
    var psiTauValue: Float
    var mathcalGthetasValue: Float
    var ellipticPValue: Float
    var IphiValue: Float
    var uplus: Float
    var uminus: Float
    var rootOfRatio: Float
    var deltaTheta: Float
    var t1: Float
    var t2: Float
    var sum: Float
    var sqrt1: Float
    var sqrt2: Float
    var uplusApprox: Float
    var epsilon: Float
    var ifInput: Bool
    var IrStatus: Int32
    var cosThetaObserverStatus: Int32
    var GphiStatus: Int32
    var mathcalGphisStatus: Int32
    var psiTauStatus: Int32
    var mathcalGthetasStatus: Int32
    var ellipticPStatus: Int32
    var IphiStatus: Int32
    var rootsResultStatus: Int32
}

struct JacobiAmDebugResult {
    var ellipticKofmValue: Float
    var yShiftValue: Float
    var intermediateResultValue: Float
    var ellipticKofmStatus: Int32
    var yShiftStatus: Int32
    var intermediateResultStatus: Int32
}

struct PhiSResult {
    var val: Float
    var status: Int32
}

protocol BufferData {
    func createBuffer(device: MTLDevice) -> MTLBuffer?
}

extension Array: BufferData where Element == Float {
    func createBuffer(device: MTLDevice) -> MTLBuffer? {
        return device.makeBuffer(bytes: self, length: MemoryLayout<Float>.size * self.count, options: []);
    }
}

struct AnyBufferData: BufferData {
    private let _createBuffer: (MTLDevice) -> MTLBuffer?
    
    init<T: BufferData>(_ bufferData: T) {
        _createBuffer = bufferData.createBuffer
    }
    
    func createBuffer(device: MTLDevice) -> MTLBuffer? {
        return _createBuffer(device)
    }
}

// TODO: Schwarzschild explicit testing may be broken since I changed the definition of the result struct
final class GeodesicGazeTests: XCTestCase {

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var computePipelineState: MTLComputePipelineState!
    var library: MTLLibrary!

    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        library = device.makeDefaultLibrary()
        
    }
    
    func readExpectedResults(filename: String) -> [EllintResult] {
        guard let fileURL = Bundle(for: type(of: self)).url(forResource: filename, withExtension: "txt") else {
            fatalError("Expected results file not found")
        }
        
        guard let content = try? String(contentsOf: fileURL) else {
            fatalError("Unable to read expected results file")
        }
        
        var expectedResults: [EllintResult] = []
        let lines = content.split(separator: "\n")
        for line in lines {
            let components = line.split(separator: " ").map { Float($0)! }
            let result = EllintResult(val: components[0], err: components[1], status: Int32(components[2]))
            expectedResults.append(result)
        }
        
        return expectedResults
    }
    
    func testEllintFInBounds() {
        let testAngles: [Float] = [
            0.0,            // Lower boundary
            0.1,            // Small angle
            0.5,            // Mid-range angle
            1.0,            // Larger angle
            1.5,            // Near upper boundary (π/2)
            Float.pi / 4   // π/4 (45 degrees)
        ]

        let testModuli: [Float] = [
            0.0,    // Lower boundary (no elliptic effect)
            0.1,    // Small modulus
            0.3,    // Small to mid-range modulus
            0.5,    // Mid-range modulus
            0.7,    // Mid to high-range modulus
            0.9    // High-range modulus
        ]
        
        let wrappedTestAngles = AnyBufferData(testAngles)
        let wrappedTestModuli = AnyBufferData(testModuli)
        let inputs: [AnyBufferData] = [wrappedTestAngles, wrappedTestModuli]
        
        let count = testAngles.count
        let resultBufferSize = count * MemoryLayout<EllintResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "ellint_F_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: EllintResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = readExpectedResults(filename: "expected_ellipticf_results")
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.val, expectedResult.val, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Non SUCCESSful status code at index \(i)")
        }
    }
    
    func testEllintFOutOfBounds() {
        let testAngles: [Float] = [Float.pi / 2.0]
        let testModuli: [Float] = [sqrt(2)]
        
        let wrappedTestAngles = AnyBufferData(testAngles)
        let wrappedTestModuli = AnyBufferData(testModuli)
        let inputs: [AnyBufferData] = [wrappedTestAngles, wrappedTestModuli]
        
        let count = testAngles.count
        let resultBufferSize = count * MemoryLayout<EllintResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "ellint_F_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: EllintResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let result1 = EllintResult(val: 0.0, err: 0.0, status: -1)
        let expectedResults = [result1]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Unexpected status code at index \(i)")
        }
    }
    
    func testEllintEInBounds() {
        let testAngles: [Float] = [
            0.0,            // Lower boundary
            0.1,            // Small angle
            0.5,            // Mid-range angle
            1.0,            // Larger angle
            1.5,            // Near upper boundary (π/2)
            Float.pi / 4   // π/4 (45 degrees)
        ]

        let testModuli: [Float] = [
            0.0,    // Lower boundary (no elliptic effect)
            0.1,    // Small modulus
            0.3,    // Small to mid-range modulus
            0.5,    // Mid-range modulus
            0.7,    // Mid to high-range modulus
            0.9    // High-range modulus
        ]
        
        let wrappedTestAngles = AnyBufferData(testAngles)
        let wrappedTestModuli = AnyBufferData(testModuli)
        let inputs: [AnyBufferData] = [wrappedTestAngles, wrappedTestModuli]
        
        let count = testAngles.count
        let resultBufferSize = count * MemoryLayout<EllintResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "ellint_E_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: EllintResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = readExpectedResults(filename: "expected_elliptice_results")

        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.val, expectedResult.val, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Non SUCCESSful status code at index \(i)")
        }
    }
    
    func testEllintPInBounds() {
        let testAngles: [Float] = [
            0.0,            // Lower boundary
            0.1,            // Small angle
            0.5,            // Mid-range angle
            1.0,            // Larger angle
            1.5,            // Near upper boundary (π/2)
            Float.pi / 4   // π/4 (45 degrees)
        ]

        let testModuli: [Float] = [
            0.0,    // Lower boundary (no elliptic effect)
            0.1,    // Small modulus
            0.3,    // Small to mid-range modulus
            0.5,    // Mid-range modulus
            0.7,    // Mid to high-range modulus
            0.9    // High-range modulus
        ]
        
        let testN: [Float] = [
            0.0,
            0.5,
            0.9,
            0.0,
            0.01,
            -0.5
        ]

        let wrappedTestAngles = AnyBufferData(testAngles)
        let wrappedTestModuli = AnyBufferData(testModuli)
        let wrappedTestN = AnyBufferData(testN)
        let inputs: [AnyBufferData] = [wrappedTestAngles, wrappedTestModuli, wrappedTestN]
        
        let count = testAngles.count
        let resultBufferSize = count * MemoryLayout<EllintResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "ellint_P_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: EllintResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = readExpectedResults(filename: "expected_ellipticp_results")

        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.val, expectedResult.val, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Non SUCCESSful status code at index \(i)")
        }
    }
    
    func testEllintPMMAInBounds() {
        let testAngles: [Float] = [
            0.5,            // Mid-range angle
            1.0,            // Larger angle
            Float.pi / 4   // π/4 (45 degrees)
        ]

        let testModuli: [Float] = [
           -0.4,    // Lower boundary (no elliptic effect)
            0.0,    // Lower boundary (no elliptic effect)
            0.3
        ]
        
        let testN: [Float] = [
            0.0,
            0.5,
            0.9,
        ]

        let wrappedTestAngles = AnyBufferData(testAngles)
        let wrappedTestModuli = AnyBufferData(testModuli)
        let wrappedTestN = AnyBufferData(testN)
        let inputs: [AnyBufferData] = [wrappedTestAngles, wrappedTestModuli, wrappedTestN]
        
        let count = testAngles.count
        let resultBufferSize = count * MemoryLayout<EllintResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "ellint_P_mma_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: EllintResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults: [EllintResult] = [
            EllintResult(val: 0.492389, err: 0, status: 0),
            EllintResult(val: 1.17882, err: 0, status: 0),
            EllintResult(val: 1.00158, err: 0, status: 0)
        ]

        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.val, expectedResult.val, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Non SUCCESSful status code at index \(i)")
        }
    }

    func testRadialRoots() {
        let M: [Float] = [1.0, 1.0, 1.0]
        let b: [Float] = [5.2, 5.31, 10.11]
        
        let wrappedM = AnyBufferData(M)
        let wrappedb = AnyBufferData(b)
        let inputs: [AnyBufferData] = [wrappedM, wrappedb]
        
        let count = M.count
        let resultBufferSize = count * MemoryLayout<simd_float4>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "radial_roots_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float4.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        // Generated via Mathematica
        let expectedResults = [simd_float4(-6.00395, 0, 2.93529, 3.06866),
                               simd_float4(-6.11681, 0, 2.69151, 3.42529),
                               simd_float4(-10.9914, 0, 2.08922, 8.90217)]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult[0], expectedResult[0], accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult[1], expectedResult[1], accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult[2], expectedResult[2], accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult[3], expectedResult[3], accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testPhiS() {
        let M:  [Float] = [1.0, 1.0, 1.0, 1.0]
        let ro: [Float] = [30.0, 30.0, 30.0, 30.0]
        let rs: [Float] = [1000.0, 1000.0, 1000.0, 1000.0]
        let b:  [Float] = [5.2, 5.31, 10.11, 21.2132034355]
        
        let wrappedM = AnyBufferData(M)
        let wrappedro = AnyBufferData(ro)
        let wrappedrs = AnyBufferData(rs)
        let wrappedb = AnyBufferData(b)
        let inputs: [AnyBufferData] = [wrappedM, wrappedro, wrappedrs, wrappedb]
        
        let count = M.count
        let resultBufferSize = count * MemoryLayout<PhiSResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "phiS_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: PhiSResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            PhiSResult(val: 9.7726,     status: 0),
            PhiSResult(val: 6.42818,    status: 0),
            PhiSResult(val: 3.3687,     status: 0),
            PhiSResult(val: 2.56081019, status: 0)
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.val, expectedResult.val, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Non SUCCESSful status code at index \(i)")
        }
    }
    
    func testNormalizeAngle() {
        let phi:      [Float] = [2.56081019]
        
        let wrappedphi = AnyBufferData(phi)
        let inputs: [AnyBufferData] = [wrappedphi]
        
        let count = phi.count
        let resultBufferSize = count * MemoryLayout<Float>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "normalize_angle_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: Float.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults: [Float] = [2.56081019]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult, expectedResult, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testSchwarzchildLense() {
        let M:      [Float] = [1.0]
        let ro:     [Float] = [30.0]
        let rs:     [Float] = [1000.0]
        let varphi: [Float] = [Float.pi / 4.0]
        let bs: [Float] = [30.0 * sin(Float.pi / 4.0)]
        
        let wrappedM = AnyBufferData(M)
        let wrappedro = AnyBufferData(ro)
        let wrappedrs = AnyBufferData(rs)
        let wrappedbs = AnyBufferData(bs)
        let inputs: [AnyBufferData] = [wrappedM, wrappedro, wrappedrs, wrappedbs]
        
        let count = M.count
        let resultBufferSize = count * MemoryLayout<SchwarzschildLenseResult>.size
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "schwarzschild_lense_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: SchwarzschildLenseResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            SchwarzschildLenseResult(varphitilde: 0.56472623, ccw: false, status: 0)
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            XCTAssertEqual(gpuResult.varphitilde, expectedResult.varphitilde, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.ccw, expectedResult.ccw, "CCW mismatch at index \(i)")
            XCTAssertEqual(gpuResult.status, expectedResult.status, "Non SUCCESSful status code at index \(i)")
        }
    }

    func runComputeShader(shaderName: String, inputs: [AnyBufferData], resultsBuffer: MTLBuffer) {
        let kernelFunction = library?.makeFunction(name: shaderName)
        computePipelineState = try! device.makeComputePipelineState(function: kernelFunction!)

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        computeEncoder.setComputePipelineState(computePipelineState)
        
        var buffers: [MTLBuffer?] = []
        for (index, input) in inputs.enumerated() {
            if let buffer = input.createBuffer(device: device) {
                computeEncoder.setBuffer(buffer, offset: 0, index: index)
                buffers.append(buffer)
            } else {
                XCTFail("Failed to create buffer for input group \(index).")
            }
        }
        
        computeEncoder.setBuffer(resultsBuffer, offset: 0, index: inputs.count)

        // Set the number of threads
        let threadsPerThreadgroup = MTLSize(width: 8, height: 1, depth: 1)
        let threadgroups = MTLSize(width: (inputs.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                                   height: 1,
                                   depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    
    func testKerrRadialRoots() {
        let a: [Float] = [0.8, 0.8, 0.2, 0.6]
        let M: [Float] = [1.0, 1.0, 1.0, 1.0]
        let eta: [Float] = [5.0, 40, 11.2, 300]
        let lambda: [Float] = [-4.0, -4, -3.3, 13]
        
        let wrappeda = AnyBufferData(a)
        let wrappedM = AnyBufferData(M)
        let wrappedEta = AnyBufferData(eta)
        let wrappedLambda = AnyBufferData(lambda)
        let inputs: [AnyBufferData] = [wrappeda, wrappedM, wrappedEta, wrappedLambda]
        
        let count = M.count
        let resultBufferSize = count * MemoryLayout<KerrRadialRootsResult>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "kerr_radial_roots_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: KerrRadialRootsResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            KerrRadialRootsResult(r1: simd_float2(x: -5.53192, y: 0),
                                  r2: simd_float2(x: 0.0582949, y: 0),
                                  r3: simd_float2(x: 2.73681 , y: -1.55977),
                                  r4: simd_float2(x: 2.73681 , y: 1.55977),
                                  status: 0),
            KerrRadialRootsResult(r1: simd_float2(x: -8.40923, y: 0),
                                  r2: simd_float2(x: 0.225317, y: 0),
                                  r3: simd_float2(x: 2.2939, y: 0),
                                  r4: simd_float2(x: 5.89001, y: 0),
                                  status: 0),
            KerrRadialRootsResult(r1: simd_float2(x: -5.5272, y: 0),
                                  r2: simd_float2(x: 0.00959553, y: 0),
                                  r3: simd_float2(x: 2.7588, y: -0.914346),
                                  r4: simd_float2(x: 2.7588, y: 0.914346),
                                  status: 0),
            KerrRadialRootsResult(r1: simd_float2(x: -22.5627, y: 0),
                                  r2: simd_float2(x: 0.127385, y: 0),
                                  r3: simd_float2(x: 1.82301, y: 0),
                                  r4: simd_float2(x: 20.6123, y: 0),
                                  status: 0)
        ]

        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            print("root: \(gpuResult)")
            XCTAssertEqual(gpuResult.r1.x, expectedResult.r1.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r1.y, expectedResult.r1.y, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r2.x, expectedResult.r2.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r2.y, expectedResult.r2.y, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r3.x, expectedResult.r3.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r3.y, expectedResult.r3.y, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r4.x, expectedResult.r4.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.r4.y, expectedResult.r4.y, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testComputePQ() {
        let a: [Float] = [0.8, 0.8, 0.2]
        let M: [Float] = [1.0, 1.0, 1.0]
        let eta: [Float] = [5.0, 40, 11.2]
        let lambda: [Float] = [-4.0, -4, -3.3]
        
        let wrappeda = AnyBufferData(a)
        let wrappedM = AnyBufferData(M)
        let wrappedEta = AnyBufferData(eta)
        let wrappedLambda = AnyBufferData(lambda)
        let inputs: [AnyBufferData] = [wrappeda, wrappedM, wrappedEta, wrappedLambda]
        
        let count = M.count
        let resultBufferSize = count * MemoryLayout<simd_float2>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "compute_pq_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float2.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            print("P,Q: \(gpuResult)")
        }
    }

    func testComputeABC() {
        let a: [Float] = [0.8, 0.8, 0.2]
        let M: [Float] = [1.0, 1.0, 1.0]
        let eta: [Float] = [5.0, 40, 11.2]
        let lambda: [Float] = [-4.0, -4, -3.3]
        
        let wrappeda = AnyBufferData(a)
        let wrappedM = AnyBufferData(M)
        let wrappedEta = AnyBufferData(eta)
        let wrappedLambda = AnyBufferData(lambda)
        let inputs: [AnyBufferData] = [wrappeda, wrappedM, wrappedEta, wrappedLambda]
        
        let count = M.count
        let resultBufferSize = count * MemoryLayout<simd_float3>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "compute_abc_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float3.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            print("A,B,C: \(gpuResult)")
        }
    }
    
    func testPow1over3() {
        let zx: [Float] = [1.0, 0.0, 3.345]
        let zy: [Float] = [0.0, 1.0, -1.2245]

        let wrappedzx = AnyBufferData(zx)
        let wrappedzy = AnyBufferData(zy)
        let inputs: [AnyBufferData] = [wrappedzx, wrappedzy]
        
        let count = zx.count
        let resultBufferSize = count * MemoryLayout<simd_float2>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "pow1over3_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float2.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            simd_float2(x: 1.0,         y: 0.0),
            simd_float2(x: 0.866025,    y: 0.5),
            simd_float2(x: 1.51678,     y: -0.178236)
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            print("gpu result: \(gpuResult)")
            print("expected result: \(expectedResult)")
            
            XCTAssertEqual(gpuResult.x, expectedResult.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.y, expectedResult.y, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testJacobiAm() {
        let u: [Float] = [5.0]
        let m: [Float] = [0.9]

        let wrappedu = AnyBufferData(u)
        let wrappedm = AnyBufferData(m)
        let inputs: [AnyBufferData] = [wrappedu, wrappedm]
        
        let count = u.count
        let resultBufferSize = count * MemoryLayout<Float>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "jacobiam_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: Float.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults: [Float] = [
            2.98598
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            print("gpu result: \(gpuResult)")
            print("expected result: \(expectedResult)")
            
            XCTAssertEqual(gpuResult, expectedResult, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testJacobiAmDebug() {
        let u: [Float] = [5.0]

        let wrappedu = AnyBufferData(u)
        let inputs: [AnyBufferData] = [wrappedu]
        
        let count = u.count
        let resultBufferSize = count * MemoryLayout<JacobiAmDebugResult>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "jacobiam_debug_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: JacobiAmDebugResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            print(gpuResult)
        }
    }

    func testKerrLensing() {
        let dummyData: [Float] = [1.0]

        let wrappedDummyData = AnyBufferData(dummyData)
        let inputs: [AnyBufferData] = [wrappedDummyData]
        
        let count = dummyData.count
        let resultBufferSize = count * MemoryLayout<KerrLenseResult>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "kerr_lense_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: KerrLenseResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        for i in 0..<gpuResults.count {
            print(gpuResults[i])
        }
    }
    
    func testKerrOther() {
        let dummyData: [Float] = [1.0]

        let wrappedDummyData = AnyBufferData(dummyData)
        let inputs: [AnyBufferData] = [wrappedDummyData]
        
        let count = dummyData.count
        let resultBufferSize = count * MemoryLayout<PhiSResult>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "other_crasher_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: PhiSResult.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        for i in 0..<gpuResults.count {
            print(gpuResults[i])
        }
    }

    func testKerr() {
        let dummyData: [Float] = [1.0]

        let wrappedDummyData = AnyBufferData(dummyData)
        let inputs: [AnyBufferData] = [wrappedDummyData]
        
        let count = dummyData.count
        let resultBufferSize = count * MemoryLayout<Result>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "crasher_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: Result.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        for i in 0..<gpuResults.count {
            print(gpuResults[i])
        }
    }
    
    func testSphericalToCartesian() {
        let r:      [Float] = [1.0]
        let theta:  [Float] = [3.14159265 / 2.0]
        let phi:    [Float] = [3.14159265 / 2.0]

        let wrappedr        = AnyBufferData(r)
        let wrappedTheta    = AnyBufferData(theta)
        let wrappedPhi      = AnyBufferData(phi)
        let inputs: [AnyBufferData] = [wrappedr, wrappedTheta, wrappedPhi]
        
        let count = r.count
        let resultBufferSize = count * MemoryLayout<simd_float3>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "spherical_to_cartesian_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float3.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            simd_float3(x: 0.0, y: 1.0, z: 0.0)
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            print("gpu result: \(gpuResult)")
            print("expected result: \(expectedResult)")
            
            XCTAssertEqual(gpuResult.x, expectedResult.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.y, expectedResult.y, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.z, expectedResult.z, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testCartesianToSpherical() {
        let x: [Float] = [0.0]
        let y: [Float] = [1.0 / sqrt(2.0)]
        let z: [Float] = [1.0 / sqrt(2.0)]

        let wrappedx = AnyBufferData(x)
        let wrappedy = AnyBufferData(y)
        let wrappedz = AnyBufferData(z)
        let inputs: [AnyBufferData] = [wrappedx, wrappedy, wrappedz]
        
        let count = x.count
        let resultBufferSize = count * MemoryLayout<simd_float3>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "cartesian_to_spherical_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float3.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            simd_float3(x: 1.0, y: 3.14159265 / 4.0, z: 3.14159265 / 2.0)
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            print("gpu result: \(gpuResult)")
            print("expected result: \(expectedResult)")
            
            XCTAssertEqual(gpuResult.x, expectedResult.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.y, expectedResult.y, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.z, expectedResult.z, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }
    
    func testRotateSpherical() {
        let pi: Float = 3.14159265;
        
        let vsR:        [Float] = [10.0]
        let vsTheta:    [Float] = [pi / 4.0]
        let vsPhi:      [Float] = [0.0]
        
        let voR:        [Float] = [10.0]
        let voTheta:    [Float] = [3.0 * pi / 4.0]
        let voPhi:      [Float] = [pi]

        let wrappedVsR      = AnyBufferData(vsR)
        let wrappedVsTheta  = AnyBufferData(vsTheta)
        let wrappedVsPhi    = AnyBufferData(vsPhi)
        
        let wrappedVoR      = AnyBufferData(voR)
        let wrappedVoTheta  = AnyBufferData(voTheta)
        let wrappedVoPhi    = AnyBufferData(voPhi)
        
        let inputs: [AnyBufferData] = [wrappedVsR, wrappedVsTheta, wrappedVsPhi, wrappedVoR, wrappedVoTheta, wrappedVoPhi]
        
        let count = vsR.count
        let resultBufferSize = count * MemoryLayout<simd_float3>.size;
        let resultsBuffer = device.makeBuffer(length: resultBufferSize, options: [])

        runComputeShader(shaderName: "rotate_spherical_coordinates_compute_kernel", inputs: inputs, resultsBuffer: resultsBuffer!)
        
        let resultsPointer = resultsBuffer?.contents().bindMemory(to: simd_float3.self, capacity: count)
        let gpuResults = Array(UnsafeBufferPointer(start: resultsPointer, count: count))
        
        let expectedResults = [
            simd_float3(x: 10.0, y: pi / 2.0, z: pi)
        ]
        
        for i in 0..<gpuResults.count {
            let gpuResult = gpuResults[i]
            let expectedResult = expectedResults[i]
            print("gpu result: \(gpuResult)")
            print("expected result: \(expectedResult)")
            
            XCTAssertEqual(gpuResult.x, expectedResult.x, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.y, expectedResult.y, accuracy: 1e-3, "Value mismatch at index \(i)")
            XCTAssertEqual(gpuResult.z, expectedResult.z, accuracy: 1e-3, "Value mismatch at index \(i)")
        }
    }

}
