//
//  BhiMixer.swift
//  MultiCamDemo
//
//  Created by Trevor Gravely on 7/16/24.
//

import MetalKit
import Foundation
import UIKit
import Photos
import simd

class BhiMixer {
    
    struct Uniforms {
        var frontTextureWidth: Int32
        var frontTextureHeight: Int32
        var backTextureWidth: Int32
        var backTextureHeight: Int32
        var mode: Int32
        var spacetimeMode: Int32
        var isBlackHoleInFront: Int32
        var vcWidthToViewWidth: Float
        var vcEdgeInViewTextureCoords: Float
        var isPipEnabled: Int32
    }
    
    struct PreComputeUniforms {
        var mode: Int32
    }
    
    struct FilterParameters {
        var spaceTimeMode: Int32
        var sourceMode: Int32
        var d: Float
        var a: Float
        var thetas: Float
        var schwarzschildMode: Int32
    }

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var precomputeCommandQueue: MTLCommandQueue!
    var textureCache: CVMetalTextureCache!
    var pipelineState: MTLRenderPipelineState!
    var computePipelineState: MTLComputePipelineState!
    var frontYTexture: MTLTexture?
    var frontUVTexture: MTLTexture?
    var frontTextureHeight: Int?
    var frontTextureWidth: Int?
    var backYTexture: MTLTexture?
    var backUVTexture: MTLTexture?
    var backTextureHeight: Int?
    var backTextureWidth: Int?
    var mode: Int32!
    
    var lutTexture: MTLTexture!
    var mmaDataTexture: MTLTexture!
    var mmaLutTexture: MTLTexture!

    var filterParameters = FilterParameters(spaceTimeMode: 0, sourceMode: 1, d: 1000, a: 0, thetas: 0, schwarzschildMode: 0)
    var needsNewLutTexture = true
    
    var filterParametersBuffer: MTLBuffer
    var uniformsBuffer: MTLBuffer
    var widthBuffer: MTLBuffer
    var debugMatrixBuffer: MTLBuffer?
    
    var totalElements: Int = 0
    var debugMatrixWidth: Int = 0
    var debugMatrixHeight: Int = 0
    
    var matrixFromMathematica: [Float]?
    
    var isBlackHoleInFront: Int32 = 1
    
    var vcWidthToViewWidth: Float?
    var vcEdgeInViewTextureCoords: Float?
    var isPipEnabled: Int32 = 1
    
    var shouldTakeScreenshot: Bool = false

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.precomputeCommandQueue = device.makeCommandQueue()
        self.mode = 0
        
        self.filterParametersBuffer = device.makeBuffer(length: MemoryLayout<FilterParameters>.size, options: .storageModeShared)!
        self.uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)!
        self.widthBuffer = device.makeBuffer(length: MemoryLayout<UInt>.size, options: .storageModeShared)!
        
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        
        createMMALutTexture()
        setupPipelines()
    }
    
    private func createMMALutTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Uint,
            width: 1080,
            height: 1920,
            mipmapped: false)
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("couldn't create texture")
        }
        
        mmaLutTexture = texture
    }
    
    private func setupPipelines() {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "preComputedFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("Pipeline state created successfully")
        } catch {
            fatalError("Failed to create pipeline state")
        }
        
        let computeFunction = library?.makeFunction(name: "precomputeLut")
        computePipelineState = try! device.makeComputePipelineState(function: computeFunction!)
    }
    
    func initializeSizeDependentData(width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 1920
        descriptor.height = 1080
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        lutTexture = device.makeTexture(descriptor: descriptor)
        print("texture width: \(lutTexture.width), texture height: \(lutTexture.height)")
        
        debugMatrixWidth = lutTexture.width;
        debugMatrixHeight = lutTexture.height;
        totalElements = debugMatrixWidth * debugMatrixHeight;
        let debugMatrixBufferSize = totalElements * MemoryLayout<simd_float3>.stride;
        
        debugMatrixBuffer = device.makeBuffer(length: debugMatrixBufferSize, options: .storageModeShared)
        
        var matrixWidth = debugMatrixWidth
        memcpy(widthBuffer.contents(), &matrixWidth, MemoryLayout<UInt>.size)
    }
    
    private func loadBinaryIntoMMALutTexture(fileName: String) {
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            fatalError("file not found")
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            fatalError("couldn't get data")
        }
        
        let pointer = (data as NSData).bytes
        
        mmaLutTexture.replace(
            region: MTLRegionMake2D(0, 0, 1080, 1920),
            mipmapLevel: 0,
            withBytes: pointer,
            bytesPerRow: MemoryLayout<UInt16>.size * 4 * 1080
        )
    }

    private func verifyMMALutTexture() {
        let textureWidth = mmaLutTexture.width
        let textureHeight = mmaLutTexture.height
        
        let bytesPerPixel = 8
        let bytesPerRow = textureWidth * bytesPerPixel
        var data = [UInt16](repeating: 0, count: 4 * textureWidth * textureHeight)
        
        mmaLutTexture.getBytes(&data,
                               bytesPerRow: bytesPerRow,
                               from: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                               mipmapLevel: 0)
        
        for row in 0..<textureHeight {
            for col in 0..<textureWidth {
                let idx = (row * textureWidth + col) * 4
                let a = data[idx]
                let b = data[idx + 1]
                let c = data[idx + 2]
                let d = data[idx + 3]
            }
        }
    }
    
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> (MTLTexture?,
                                                                    MTLTexture?,
                                                                    Int,
                                                                    Int)? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var yTexture: CVMetalTexture?
        var uvTexture: CVMetalTexture?
        
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .r8Unorm, width, height, 0, &yTexture)
        
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .rg8Unorm, width / 2, height / 2, 1, &uvTexture)
        
        if yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess {
            let yMetalTexture = CVMetalTextureGetTexture(yTexture!)
            let uvMetalTexture = CVMetalTextureGetTexture(uvTexture!)
            return (yMetalTexture, uvMetalTexture, width, height)
        }

        print("Couldn't create texture")
        return nil
    }

    func mix(frontCameraPixelBuffer: CVPixelBuffer?,
             backCameraPixelBuffer: CVPixelBuffer?,
             in view: MTKView) {
        
        guard let drawable = view.currentDrawable else {
            print("Currentdrawable is nil")
            return
        }
        
        // Only need to do compute pass if flat or Schwarzschild
        if needsNewLutTexture {
            if filterParameters.spaceTimeMode != 2 {
                guard let computeCommandBuffer = commandQueue.makeCommandBuffer() else {
                    print("Couldn't create command buffer")
                    return
                }
                print("computing new lut texture")
                
                let computeEncoder = computeCommandBuffer.makeComputeCommandEncoder()!
                computeEncoder.setComputePipelineState(computePipelineState)
                
                var otherFilterParameters = filterParameters
                memcpy(filterParametersBuffer.contents(), &otherFilterParameters, MemoryLayout<FilterParameters>.size)
                
                computeEncoder.setBuffer(filterParametersBuffer,    offset: 0, index: 0)
                computeEncoder.setBuffer(debugMatrixBuffer,         offset: 0, index: 1)
                computeEncoder.setBuffer(widthBuffer,               offset: 0, index: 2)
                
                computeEncoder.setTexture(lutTexture,                          index: 0)
                
                /*
                 * lutTexture.dimension + groupSize - 1 / groupSize is just
                 * lutTexture.dimension / groupSize rounded up. This guarantees
                 * that group * groupSize covers the full texture width / height.
                 */
                let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
                let threadGroups = MTLSize(width: (lutTexture.width + 15) / 16,
                                           height: (lutTexture.height + 15) / 16,
                                           depth: 1)
                
                computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                computeEncoder.endEncoding()
                
                computeCommandBuffer.commit()
                computeCommandBuffer.waitUntilCompleted()
                
                
                /*
                 if filterParameters.spaceTimeMode == 2 && filterParameters.sourceMode == 0 {
                 let postProcessingEncoder = computeCommandBuffer.makeComputeCommandEncoder()!
                 postProcessingEncoder.setComputePipelineState(postProcessingPipelineState)
                 
                 var sliceWidth = 50
                 var textureWidth = lutTexture.height // Account for weird convention
                 
                 postProcessingEncoder.setTexture(lutTexture,                                    index: 0)
                 postProcessingEncoder.setBytes(&sliceWidth, length: MemoryLayout<uint>.size,    index: 0)
                 postProcessingEncoder.setBytes(&textureWidth, length: MemoryLayout<uint>.size,  index: 1)
                 postProcessingEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                 postProcessingEncoder.endEncoding()
                 }
                 */
                
                
                // if filterParameters.spaceTimeMode == 2 && filterParameters.sourceMode == 0 {
                // cpuPostProcess(rowInterp: fEqual(0.01, filterParameters.a))
                /*
                 if filterParameters.a == 0.9 {
                 logLUT()
                 }
                 */
                // cpuPostProcessOther()
                // cpuPostProcessStatic()
                // findLayers()
                // }
            } else {
                
                /*
                 * If in Kerr, just need to load in the selected lut texture generated by
                 * MMA. 
                 */
                
                if fEqual(filterParameters.a, 0.5) {
                    loadBinaryIntoMMALutTexture(fileName: "lut-texture-a-0-5")
                } else if fEqual(filterParameters.a, 0.9) {
                    loadBinaryIntoMMALutTexture(fileName: "lut-texture-a-0-9")
                } else if fEqual(filterParameters.a, 0.99) {
                    loadBinaryIntoMMALutTexture(fileName: "lut-texture-a-0-99")
                } else if fEqual(filterParameters.a, 0.999) {
                    loadBinaryIntoMMALutTexture(fileName: "lut-texture-a-0-999")
                } else {
                    fatalError("spin value not valid")
                }
                
                verifyMMALutTexture()
            }
            
            needsNewLutTexture = false
        }
        
        guard let renderCommandBuffer = commandQueue.makeCommandBuffer() else {
            print("Couldn't create command buffer")
            return
        }
        
        if let frontCameraPixelBuffer = frontCameraPixelBuffer {
            let textures = createTexture(from: frontCameraPixelBuffer)
            frontYTexture = textures?.0
            frontUVTexture = textures?.1
            frontTextureWidth = textures?.2
            frontTextureHeight = textures?.3
        }
        if let backCameraPixelBuffer = backCameraPixelBuffer {
            let textures = createTexture(from: backCameraPixelBuffer)
            backYTexture = textures?.0
            backUVTexture = textures?.1
            backTextureWidth = textures?.2
            backTextureHeight = textures?.3
        }
        
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let frontYTexture = frontYTexture,
              let frontUVTexture = frontUVTexture,
              let frontTextureWidth = frontTextureWidth,
              let frontTextureHeight = frontTextureHeight,
              let backYTexture = backYTexture,
              let backUVTexture = backUVTexture,
              let backTextureWidth = backTextureWidth,
              let backTextureHeight = backTextureHeight,
              let vcEdgeInViewTextureCoords = vcEdgeInViewTextureCoords,
              let vcWidthToViewWidth = vcWidthToViewWidth else {
            print("returning from mix")
            return
        }
        
        var uniforms = Uniforms(frontTextureWidth: Int32(frontTextureWidth),
                                frontTextureHeight: Int32(frontTextureHeight),
                                backTextureWidth: Int32(backTextureWidth),
                                backTextureHeight: Int32(backTextureHeight),
                                mode: filterParameters.sourceMode,
                                spacetimeMode: filterParameters.spaceTimeMode,
                                isBlackHoleInFront: isBlackHoleInFront,
                                vcWidthToViewWidth: vcWidthToViewWidth,
                                vcEdgeInViewTextureCoords: vcEdgeInViewTextureCoords,
                                isPipEnabled: isPipEnabled)
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
        
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        if renderPassDescriptor.colorAttachments[0].texture == nil {
            print("texture is null")
            return
        }

        let renderEncoder = renderCommandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(frontYTexture, index: 0)
        renderEncoder.setFragmentTexture(frontUVTexture, index: 1)
        renderEncoder.setFragmentTexture(backYTexture, index: 2)
        renderEncoder.setFragmentTexture(backUVTexture, index: 3)
        renderEncoder.setFragmentTexture(lutTexture, index: 4)
        renderEncoder.setFragmentTexture(mmaLutTexture, index: 5)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        
        renderCommandBuffer.present(drawable)
        renderCommandBuffer.commit()
        renderCommandBuffer.waitUntilCompleted()
        
        if shouldTakeScreenshot {
            takeScreenshot(drawable: drawable)
            shouldTakeScreenshot = false
        }
    }
    
    private func takeScreenshot(drawable: CAMetalDrawable) {
        guard let screenshotImage = textureToImage(drawable.texture) else {
            print("unable to take convert texture to ui image")
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: screenshotImage)
        }) { success, error in
            if let error = error {
                print("error saving to photos: \(error.localizedDescription)")
            } else {
                print("successfully saved")
            }
        }
    }
    
    private func textureToImage(_ texture: MTLTexture) -> UIImage? {
        let ciContext = CIContext(mtlDevice: device)
        guard var ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            print("Failed to create ciimage")
            return nil
        }
        
        let transform = CGAffineTransformMake(1, 0, 0, -1, 0, ciImage.extent.size.height)
        ciImage = ciImage.transformed(by: transform)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create cgimage")
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)
        
        return uiImage
    }
    
    private func cpuPostProcessOther() {
        testSplineParameters()
        
        let textureWidth = lutTexture.width
        let textureHeight = lutTexture.height
        
        let bytesPerPixel = 16
        let bytesPerRow = textureWidth * bytesPerPixel
        
        var data = [Float](repeating: 0, count: textureHeight * textureWidth * 4)
        
        lutTexture.getBytes(&data,
                            bytesPerRow: bytesPerRow,
                            from: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                            mipmapLevel: 0)
        
        let shadowWidth = 180
        let startCol = textureWidth / 2 - shadowWidth / 2
        let endCol = textureWidth / 2 + shadowWidth / 2
        
        let seekWidth = 40
        let seekStartRow = textureHeight / 2 - seekWidth / 2
        let seekEndRow = textureHeight / 2 + seekWidth / 2
        
        let combinedRange = Array(0..<startCol) + Array(endCol..<textureWidth)
        
        var col = 700
        for row in 0..<textureHeight {
            let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
            if fEqual(data[arrIndex + 2], 0.0) && fEqual(data[arrIndex + 3], 0.0) {
                print("xy data before: \(row), \(data[arrIndex + 1])")
            }
        }

        /*
         * For each column (horizontal slice in image), loop through
         * a set number of rows centered in the middle of the images
         * and interpolate from one side to the other.
         */
        for col in combinedRange {
            var errorCount = 0
            var rowIdxOfFirstError = -1
            var rowIdxOfLastError = -1
            for row in seekStartRow..<seekEndRow {
                let index = rowColToArrIdx(row: row, col: col, width: textureWidth)
                // If error status code
                if !fEqual(data[index + 2], 0.0) || !fEqual(data[index + 3], 0.0) {
                    if rowIdxOfFirstError == -1 {
                        rowIdxOfFirstError = row
                    }
                    rowIdxOfLastError = row
                    errorCount += 1
                }
            }
            
            if errorCount == 0 { continue }
            print("col: \(col) error count: \(errorCount)")
            
            let buffer = 10
            let startRow = (rowIdxOfFirstError - buffer)
            let endRow = (rowIdxOfLastError + buffer)

            let arrIdxOfOneAboveStartPixel = rowColToArrIdx(row: startRow - 1, col: col, width: textureWidth)
            let arrIdxOfStartPixel = rowColToArrIdx(row: startRow, col: col, width: textureWidth)
            let arrIdxOfEndPixel = rowColToArrIdx(row: endRow, col: col, width: textureWidth)
            let arrIdxOfOneBelowEndPixel = rowColToArrIdx(row: endRow + 1, col: col, width: textureWidth)

            let oneAboveStartPixelx = data[arrIdxOfOneAboveStartPixel]
            let oneAboveStartPixely = data[arrIdxOfOneAboveStartPixel + 1]
            
            let startPixelx = data[arrIdxOfStartPixel]
            let startPixely = data[arrIdxOfStartPixel + 1]
            
            let endPixelx = data[arrIdxOfEndPixel]
            let endPixely = data[arrIdxOfEndPixel + 1]
            
            let oneBelowEndPixelx = data[arrIdxOfOneBelowEndPixel]
            let oneBelowEndPixely = data[arrIdxOfOneBelowEndPixel + 1]

            // We compute a four point spline interpolation in both channels
            let xChannelKValues = computeFourPointSplineParameters(x0: Float(startRow - 1),     y0: oneAboveStartPixelx,
                                                                   x1: Float(startRow),         y1: startPixelx,
                                                                   x2: Float(endRow),           y2: endPixelx,
                                                                   x3: Float(endRow + 1),       y3: oneBelowEndPixelx)
            
            let yChannelKValues = computeFourPointSplineParameters(x0: Float(startRow - 1),     y0: oneAboveStartPixely,
                                                                   x1: Float(startRow),         y1: startPixely,
                                                                   x2: Float(endRow),           y2: endPixely,
                                                                   x3: Float(endRow + 1),       y3: oneBelowEndPixely)

            // For passing to computeSplineValue.
            let x1          = Float(startRow)
            let x2          = Float(endRow)
            
            let y1xChannel  = startPixelx
            let y2xChannel  = endPixelx
            let k1xChannel  = xChannelKValues.1
            let k2xChannel  = xChannelKValues.2

            let y1yChannel  = startPixely
            let y2yChannel  = endPixely
            let k1yChannel  = yChannelKValues.1
            let k2yChannel  = yChannelKValues.2
            
            // 1080 / 2
            let middleRow = 540;
            let middleRowArrIdx = rowColToArrIdx(row: middleRow, col: col, width: textureWidth)
            let oneAboveMiddleRowArrIdx = rowColToArrIdx(row: middleRow - 1, col: col, width: textureWidth)
            data[middleRowArrIdx + 2] = data[oneAboveMiddleRowArrIdx + 2]
            data[middleRowArrIdx + 3] = data[oneAboveMiddleRowArrIdx + 3]

            for row in startRow...endRow {
                let prevArrIndex = rowColToArrIdx(row: row - 1, col: col, width: textureWidth)
                let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                let interpx = computeSplineValue(x1: x1, x2: x2,
                                                 y1: y1xChannel, y2: y2xChannel,
                                                 k1: k1xChannel, k2: k2xChannel, Float(row))
                
                let interpy = computeSplineValue(x1: x1, x2: x2,
                                                 y1: y1yChannel, y2: y2yChannel,
                                                 k1: k1yChannel, k2: k2yChannel, Float(row))

                data[arrIndex]      = interpx
                data[arrIndex + 1]  = interpy
            }
        }
        
        col = 700
        for row in 0..<textureHeight {
            let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
            if fEqual(data[arrIndex + 2], 0.0) && fEqual(data[arrIndex + 3], 0.0) {
                print("xy data after: \(row), \(data[arrIndex + 1])")
            }
        }
        
        /*
        var redCol = 665
        for row in 0..<textureHeight {
            let arrIndex = rowColToArrIdx(row: row, col: redCol, width: textureWidth)
            data[arrIndex + 2] = 10.0
            data[arrIndex + 3] = 10.0
        }
        */
        
        let rowInterp = true
        if rowInterp {
            let shadowHeight = 450
            let startRow = textureHeight / 2 - shadowHeight / 2
            let endRow = textureHeight / 2 + shadowHeight / 2
            
            let seekWidth = 10
            let startCol = textureWidth / 2 - seekWidth / 2
            let endCol = textureWidth / 2 + seekWidth / 2
            
            let combinedRange = Array(0..<startRow) + Array(endRow..<textureHeight)
            
            for row in combinedRange {
                var errorCount = 0
                var colIdxOfFirstError = -1
                var colIdxOfLastError = -1
                for col in startCol..<endCol {
                    let index = rowColToArrIdx(row: row, col: col, width: textureWidth)
                    if fEqual(data[index + 2], 1.0) && fEqual(data[index + 3], 0.0) {
                        if colIdxOfFirstError == -1 {
                            colIdxOfFirstError = col
                        }
                        colIdxOfLastError = col
                        errorCount += 1
                    }
                }
                
                if errorCount == 0 { continue }
                print("row: \(row) error count: \(errorCount)")
                
                let colIdxOfLeftPixel = (colIdxOfFirstError - 1)
                let colIdxOfRightPixel = (colIdxOfLastError + 1)
                let arrIdxOfLeftPixel = rowColToArrIdx(row: row, col: colIdxOfLeftPixel, width: textureWidth)
                let arrIdxOfRightPixel = rowColToArrIdx(row: row, col: colIdxOfRightPixel, width: textureWidth)
                
                let widthInCols = colIdxOfRightPixel - colIdxOfLeftPixel + 1
                
                let leftPixelx = data[arrIdxOfLeftPixel]
                let leftPixely = data[arrIdxOfLeftPixel + 1]
                let rightPixelx = data[arrIdxOfRightPixel]
                let rightPixely = data[arrIdxOfRightPixel + 1]
                
                for col in colIdxOfFirstError...colIdxOfLastError {
                    let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                    
                    let factor: Float = Float(col - colIdxOfLeftPixel) / Float(widthInCols)
                    
                    let interpx = mix(leftPixelx, rightPixelx, factor)
                    let interpy = mix(leftPixely, rightPixely, factor)
                    
                    data[arrIndex]      = interpx
                    data[arrIndex + 1]  = interpy
                    data[arrIndex + 2]  = 0.0
                    data[arrIndex + 3]  = 0.0
                }
            }
        }

        lutTexture.replace(region: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                           mipmapLevel: 0,
                           withBytes: data,
                           bytesPerRow: bytesPerRow)
    }
    
    private func logLUT() {
        let textureWidth = lutTexture.width
        let textureHeight = lutTexture.height
        
        let bytesPerPixel = 16
        let bytesPerRow = textureWidth * bytesPerPixel
        
        var data = [Float](repeating: 0, count: textureHeight * textureWidth * 4)
        
        lutTexture.getBytes(&data,
                            bytesPerRow: bytesPerRow,
                            from: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                            mipmapLevel: 0)
        
        let directoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = directoryPath.appendingPathComponent("lut-texture-statuses-asdf.txt")
        
        var writeOutput: String = ""
        for col in 0..<textureWidth {
            for row in 0..<textureHeight {
                let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                
                let printCode: Int;
                if (fEqual(data[arrIndex + 2], 0.0) && fEqual(data[arrIndex + 3], 0.0)) {
                    printCode = 0;
                } else if (fEqual(data[arrIndex + 2], 0.0) && fEqual(data[arrIndex + 3], 1.0)) {
                    printCode = 1;
                } else {
                    printCode = 2;
                }
                
                if (row == textureHeight - 1) {
                    writeOutput += "\(data[arrIndex]) \(data[arrIndex + 1]) \(printCode)"
                } else {
                    writeOutput += "\(data[arrIndex]) \(data[arrIndex + 1]) \(printCode),"
                }
            }
            writeOutput += "\n"
        }
        
        do {
            try writeOutput.write(to: filePath, atomically: true, encoding: .utf8)
            print("wrote to log file: \(filePath.path)")
        } catch {
            print("Failed to write to log file: \(error)")
        }
    }

    private func cpuPostProcessStatic() {
        testSplineParameters()
        
        let textureWidth = lutTexture.width
        let textureHeight = lutTexture.height
        
        let bytesPerPixel = 16
        let bytesPerRow = textureWidth * bytesPerPixel
        
        var data = [Float](repeating: 0, count: textureHeight * textureWidth * 4)
        
        lutTexture.getBytes(&data,
                            bytesPerRow: bytesPerRow,
                            from: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                            mipmapLevel: 0)
        
        let shadowWidth = 120
        let startCol = textureWidth / 2 - shadowWidth / 2
        let endCol = textureWidth / 2 + shadowWidth / 2
        
        let seekWidth = 50
        let startRow = textureHeight / 2 - seekWidth / 2
        let endRow = textureHeight / 2 + seekWidth / 2
        
        let combinedRange = Array(0..<startCol) + Array(endCol..<textureWidth)

        /*
         * For each column (horizontal slice in image), loop through
         * a set number of rows centered in the middle of the images
         * and interpolate from one side to the other.
         */
        for col in combinedRange {
            
            let arrIdxOfOneAboveStartPixel = rowColToArrIdx(row: startRow - 1, col: col, width: textureWidth)
            let arrIdxOfStartPixel = rowColToArrIdx(row: startRow, col: col, width: textureWidth)
            let arrIdxOfEndPixel = rowColToArrIdx(row: endRow, col: col, width: textureWidth)
            let arrIdxOfOneBelowEndPixel = rowColToArrIdx(row: endRow + 1, col: col, width: textureWidth)

            let oneAboveStartPixelx = data[arrIdxOfOneAboveStartPixel]
            let oneAboveStartPixely = data[arrIdxOfOneAboveStartPixel + 1]
            
            let startPixelx = data[arrIdxOfStartPixel]
            let startPixely = data[arrIdxOfStartPixel + 1]
            
            let endPixelx = data[arrIdxOfEndPixel]
            let endPixely = data[arrIdxOfEndPixel + 1]
            
            let oneBelowEndPixelx = data[arrIdxOfOneBelowEndPixel]
            let oneBelowEndPixely = data[arrIdxOfOneBelowEndPixel + 1]

            // We compute a four point spline interpolation in both channels
            let xChannelKValues = computeFourPointSplineParameters(x0: Float(arrIdxOfOneAboveStartPixel), y0: oneAboveStartPixelx,
                                                                   x1: Float(arrIdxOfStartPixel),         y1: startPixelx,
                                                                   x2: Float(arrIdxOfEndPixel),           y2: endPixelx,
                                                                   x3: Float(arrIdxOfOneBelowEndPixel),   y3: oneBelowEndPixelx)
            
            let yChannelKValues = computeFourPointSplineParameters(x0: Float(arrIdxOfOneAboveStartPixel), y0: oneAboveStartPixely,
                                                                   x1: Float(arrIdxOfStartPixel),         y1: startPixely,
                                                                   x2: Float(arrIdxOfEndPixel),           y2: endPixely,
                                                                   x3: Float(arrIdxOfOneBelowEndPixel),   y3: oneBelowEndPixely)

            // For passing to computeSplineValue.
            let x1          = Float(arrIdxOfStartPixel)
            let x2          = Float(arrIdxOfEndPixel)
            
            let y1xChannel  = startPixelx
            let y2xChannel  = endPixelx
            let k1xChannel  = xChannelKValues.1
            let k2xChannel  = xChannelKValues.2

            let y1yChannel  = startPixely
            let y2yChannel  = endPixely
            let k1yChannel  = yChannelKValues.1
            let k2yChannel  = yChannelKValues.2
            
            
            var numErroredRows = 0
            for row in startRow...endRow {
                let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                let currX = data[arrIndex]
                let currY = data[arrIndex + 1]
                let currErr1 = data[arrIndex + 2]
                let currErr2 = data[arrIndex + 3]
                
                if fEqual(currErr1, 0.0) && fEqual(currErr2, 0.0) {
                    print("row: \(row) \t val: \(currX)")
                } else {
                    numErroredRows = numErroredRows + 1
                }

                /*
                let interpx = mix(startPixelx, endPixelx, factor)
                let interpy = mix(startPixely, endPixely, factor)
                */
                let interpx = computeSplineValue(x1: x1, x2: x2,
                                                 y1: y1xChannel, y2: y2xChannel,
                                                 k1: k1xChannel, k2: k2xChannel, Float(arrIndex))
                
                let interpy = computeSplineValue(x1: x1, x2: x2,
                                                 y1: y1yChannel, y2: y2yChannel,
                                                 k1: k1yChannel, k2: k2yChannel, Float(arrIndex))

                data[arrIndex]      = interpx
                data[arrIndex + 1]  = interpy
                data[arrIndex + 2]  = 0.0
                data[arrIndex + 3]  = 0.0
            }
            print("col: \(col) \t numErrors: \(numErroredRows)")
        }
        
        /*
        for col in combinedRange {
            for row in startRow...endRow {
                let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                data[arrIndex] = 0.0
                data[arrIndex + 1] = 0.0
                data[arrIndex + 2] = 10.0
                data[arrIndex + 3] = 10.0
            }
        }
        */

        lutTexture.replace(region: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                           mipmapLevel: 0,
                           withBytes: data,
                           bytesPerRow: bytesPerRow)
    }
    
    private func printMatrix(matrix: [[Float]]) {
        for row in matrix {
            for value in row {
                print(String(format: "%.2f", value), terminator: "\t")
            }
            print()
        }
    }
    
    private func testInverse() {
        let matrix: [[Float]] = [
            [4, 7, 2, 3],
            [3, 6, 1, 4],
            [2, 5, 3, 5],
            [1, 8, 7, 9]
        ]
        
        if let invertedMatrix = inverseMatrix4x4(matrix: matrix) {
            printMatrix(matrix: invertedMatrix)
        }
    }
    
    private func testSplineParameters() {
        let res = computeFourPointSplineParameters(x0: -2.0944, y0: -0.866925,
                                                   x1: -1.5708, y1: -1.0,
                                                   x2: -1.0472, y2: -0.866025,
                                                   x3: -0.523599, y3: -0.5)
        print(res)
    }
    
    // Operates under the assumption that the x value is always in the 2nd of the
    // 3 intervals (4 point spline).
    private func computeSplineValue(x1: Float, x2: Float, y1: Float, y2: Float, k1: Float, k2: Float, _ x: Float) -> Float {
        let t = (x - x1) / (x2 - x1)
        let a = k1 * (x2 - x1) - (y2 - y1)
        let b = -1.0 * k2 * (x2 - x1) + (y2 - y1)
        
        return (1.0 - t) * y1 + t * y2 + t * (1.0 - t) * ((1.0 - t) * a + t * b)
    }
    
    private func computeFourPointSplineParameters(x0: Float, y0: Float,
                                                  x1: Float, y1: Float,
                                                  x2: Float, y2: Float,
                                                  x3: Float, y3: Float) -> (Float, Float, Float, Float) {
        let a11 = 2.0 / (x1 - x0);
        let a12 = 1.0 / (x1 - x0);
        
        let a21 = 1.0 / (x1 - x0);
        let a22 = 2.0 * ((1.0 / (x1 - x0)) + (1.0 / (x2 - x1)));
        let a23 = 1.0 / (x2 - x1);
        
        let a32 = 1.0 / (x2 - x1);
        let a33 = 2.0 * ((1.0 / (x2 - x1)) + (1.0 / (x3 - x2)));
        let a34 = 1.0 / (x3 - x2);
        
        let a43 = 1.0 / (x3 - x2);
        let a44 = 2.0 / (x3 - x2);
        
        let b1 = 3.0 * ((y1 - y0)/((x1 - x0) * (x1 - x0)));
        let b2 = 3.0 * (((y1 - y0) / ((x1 - x0) * (x1 - x0))) + ((y2 - y1) / ((x2 - x1) * (x2 - x1))));
        let b3 = 3.0 * (((y2 - y1) / ((x2 - x1) * (x2 - x1))) + ((y3 - y2) / ((x3 - x2) * (x3 - x2))));
        let b4 = 3.0 * ((y3 - y2)/((x3 - x2) * (x3 - x2)));
        
        let A: [[Float]] = [
            [a11, a12, 0.0, 0.0],
            [a21, a22, a23, 0.0],
            [0.0, a32, a33, a34],
            [0.0, 0.0, a43, a44]
        ]
        
        guard let invertedMatrix = inverseMatrix4x4(matrix: A) else {
            fatalError("No inverse")
        }
        
        let k1 = b1 * invertedMatrix[0][0] + b2 * invertedMatrix[0][1] + b3 * invertedMatrix[0][2] + b4 * invertedMatrix[0][3]
        let k2 = b1 * invertedMatrix[1][0] + b2 * invertedMatrix[1][1] + b3 * invertedMatrix[1][2] + b4 * invertedMatrix[1][3]
        let k3 = b1 * invertedMatrix[2][0] + b2 * invertedMatrix[2][1] + b3 * invertedMatrix[2][2] + b4 * invertedMatrix[2][3]
        let k4 = b1 * invertedMatrix[3][0] + b2 * invertedMatrix[3][1] + b3 * invertedMatrix[3][2] + b4 * invertedMatrix[3][3]

        return (k1, k2, k3, k4);
    }
    
    func inverseMatrix4x4(matrix: [[Float]]) -> [[Float]]? {
        let determinant = determinant4x4(matrix: matrix)
        
        if determinant == 0 {
            return nil
        }
        
        let cofactors = cofactor4x4(matrix: matrix)
        let adjugate = transpose(matrix: cofactors)
        
        var inverse = [[Float]](repeating: [Float](repeating: 0.0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                inverse[i][j] = adjugate[i][j] / determinant
            }
        }
        
        return inverse
    }
    
    private func determinant3x3(matrix: [[Float]]) -> Float {
        let a = matrix[0][0]
        let b = matrix[0][1]
        let c = matrix[0][2]
        
        let d = matrix[1][0]
        let e = matrix[1][1]
        let f = matrix[1][2]
        
        let g = matrix[2][0]
        let h = matrix[2][1]
        let i = matrix[2][2]
        
        return  a * (e * i - f * h) -
                b * (d * i - f * g) +
                c * (d * h - e * g)
    }
    
    private func determinant4x4(matrix: [[Float]]) -> Float {
        let a = matrix[0][0]
        let b = matrix[0][1]
        let c = matrix[0][2]
        let d = matrix[0][3]
        
        let e = matrix[1][0]
        let f = matrix[1][1]
        let g = matrix[1][2]
        let h = matrix[1][3]
        
        let i = matrix[2][0]
        let j = matrix[2][1]
        let k = matrix[2][2]
        let l = matrix[2][3]
        
        let m = matrix[3][0]
        let n = matrix[3][1]
        let o = matrix[3][2]
        let p = matrix[3][3]
        
        return  a * determinant3x3(matrix: [[f,g,h], [j,k,l], [n,o,p]]) -
                b * determinant3x3(matrix: [[e,g,h], [i,k,l], [m,o,p]]) +
                c * determinant3x3(matrix: [[e,f,h], [i,j,l], [m,n,p]]) -
                d * determinant3x3(matrix: [[e,f,g], [i,j,k], [m,n,o]])
    }
    
    private func cofactor4x4(matrix: [[Float]]) -> [[Float]] {
        var cofactors = [[Float]](repeating: [Float](repeating: 0.0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                var submatrix = [[Float]]()
                for k in 0..<4 {
                    if k != i {
                        var row = [Float]()
                        for l in 0..<4 {
                            if l != j {
                                row.append(matrix[k][l])
                            }
                        }
                        submatrix.append(row)
                    }
                }
                cofactors[i][j] = determinant3x3(matrix: submatrix) * ((i + j) % 2 == 0 ? 1 : -1)
            }
        }
        
        return cofactors
    }
    
    private func transpose(matrix: [[Float]]) -> [[Float]] {
        let rowCount = matrix.count
        let colCount = matrix[0].count
        var transMatrix = [[Float]](repeating: [Float](repeating: 0.0, count: rowCount), count: colCount)
        
        for i in 0..<rowCount {
            for j in 0..<colCount {
                transMatrix[i][j] = matrix[j][i]
            }
        }
        
        return transMatrix
    }

    private func fEqual(_ a: Float, _ b: Float, epsilon: Float = 1e-6) -> Bool {
        return abs(a - b) < epsilon
    }
    
    private func mix(_ x: Float, _ y: Float, _ a: Float) -> Float {
        return x * (1.0 - a) + y * a;
    }
    
    private func rowColToArrIdx(row: Int, col: Int, width: Int) -> Int {
        return row * width * 4 + col * 4
    }
}








/*
private func printDebugMatrixContents() {
    let dataPointer = debugMatrixBuffer?.contents().bindMemory(to: simd_float3.self, capacity: totalElements)
    let matrixData = Array(UnsafeBufferPointer(start: dataPointer, count: totalElements))

    var matrixResult: [[simd_float3]] = Array(repeating: Array(repeating: simd_float3(0,0,0), count: debugMatrixWidth), count: debugMatrixHeight);

    for y in 0..<debugMatrixHeight {
        for x in 0..<debugMatrixWidth {
            matrixResult[y][x] = matrixData[y * debugMatrixWidth + x]
        }
    }

    for (i, row) in matrixResult.enumerated() {
        var numError = 0;
        for (_, vector) in row.enumerated() {
            if (vector.z == -1) {
                numError += 1;
            }
        }
        print("row: \(i) numError: \(numError)")
    }

    _ = matrixResult[0][0]
}
*/

/*
private func cpuPostProcess(rowInterp: Bool) {
    let textureWidth = lutTexture.width
    let textureHeight = lutTexture.height
    
    let bytesPerPixel = 16
    let bytesPerRow = textureWidth * bytesPerPixel
    
    var data = [Float](repeating: 0, count: textureHeight * textureWidth * 4)
    
    lutTexture.getBytes(&data,
                        bytesPerRow: bytesPerRow,
                        from: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                        mipmapLevel: 0)
    
    let shadowWidth = 120
    let startCol = textureWidth / 2 - shadowWidth / 2
    let endCol = textureWidth / 2 + shadowWidth / 2
    
    let seekWidth = 30
    let startRow = textureHeight / 2 - seekWidth / 2
    let endRow = textureHeight / 2 + seekWidth / 2
    
    let combinedRange = Array(0..<startCol) + Array(endCol..<textureWidth)

    for col in combinedRange {
        var errorCount = 0
        var rowIdxOfFirstError = -1
        var rowIdxOfLastError = -1
        for row in startRow..<endRow {
            let index = rowColToArrIdx(row: row, col: col, width: textureWidth)
            // If error status code
            if fEqual(data[index + 2], 1.0) && fEqual(data[index + 3], 0.0) {
                if rowIdxOfFirstError == -1 {
                    rowIdxOfFirstError = row
                }
                rowIdxOfLastError = row
                errorCount += 1
            }
        }
        
        if errorCount == 0 { continue }
        print("col: \(col) error count: \(errorCount)")
        
        // Increasing row -> "lower"
        let rowIdxOfUpperPixel = (rowIdxOfFirstError - 1)
        let rowIdxOfLowerPixel = (rowIdxOfLastError + 1)
        let arrIdxOfUpperPixel = rowColToArrIdx(row: rowIdxOfUpperPixel, col: col, width: textureWidth)
        let arrIdxOfLowerPixel = rowColToArrIdx(row: rowIdxOfLowerPixel, col: col, width: textureWidth)

        let widthInRows = rowIdxOfLowerPixel - rowIdxOfUpperPixel + 1
        
        let upperPixelx = data[arrIdxOfUpperPixel]
        let upperPixely = data[arrIdxOfUpperPixel + 1]
        let lowerPixelx = data[arrIdxOfLowerPixel]
        let lowerPixely = data[arrIdxOfLowerPixel + 1]
        
        for row in rowIdxOfFirstError...rowIdxOfLastError {
            let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
            
            let factor: Float = Float(row - rowIdxOfUpperPixel) / Float(widthInRows)
            
            let interpx = mix(upperPixelx, lowerPixelx, factor)
            let interpy = mix(upperPixely, lowerPixely, factor)
            
            data[arrIndex]      = interpx
            data[arrIndex + 1]  = interpy
            data[arrIndex + 2]  = 0.0
            data[arrIndex + 3]  = 0.0
        }
    }
    
    if rowInterp {
        let shadowHeight = 450
        let startRow = textureHeight / 2 - shadowHeight / 2
        let endRow = textureHeight / 2 + shadowHeight / 2
        
        let seekWidth = 10
        let startCol = textureWidth / 2 - seekWidth / 2
        let endCol = textureWidth / 2 + seekWidth / 2
        
        let combinedRange = Array(0..<startRow) + Array(endRow..<textureHeight)
        
        for row in combinedRange {
            var errorCount = 0
            var colIdxOfFirstError = -1
            var colIdxOfLastError = -1
            for col in startCol..<endCol {
                let index = rowColToArrIdx(row: row, col: col, width: textureWidth)
                if fEqual(data[index + 2], 1.0) && fEqual(data[index + 3], 0.0) {
                    if colIdxOfFirstError == -1 {
                        colIdxOfFirstError = col
                    }
                    colIdxOfLastError = col
                    errorCount += 1
                }
            }
            
            if errorCount == 0 { continue }
            print("row: \(row) error count: \(errorCount)")
            
            let colIdxOfLeftPixel = (colIdxOfFirstError - 1)
            let colIdxOfRightPixel = (colIdxOfLastError + 1)
            let arrIdxOfLeftPixel = rowColToArrIdx(row: row, col: colIdxOfLeftPixel, width: textureWidth)
            let arrIdxOfRightPixel = rowColToArrIdx(row: row, col: colIdxOfRightPixel, width: textureWidth)
            
            let widthInCols = colIdxOfRightPixel - colIdxOfLeftPixel + 1
            
            let leftPixelx = data[arrIdxOfLeftPixel]
            let leftPixely = data[arrIdxOfLeftPixel + 1]
            let rightPixelx = data[arrIdxOfRightPixel]
            let rightPixely = data[arrIdxOfRightPixel + 1]
            
            for col in colIdxOfFirstError...colIdxOfLastError {
                let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                
                let factor: Float = Float(col - colIdxOfLeftPixel) / Float(widthInCols)
                
                let interpx = mix(leftPixelx, rightPixelx, factor)
                let interpy = mix(leftPixely, rightPixely, factor)
                
                data[arrIndex]      = interpx
                data[arrIndex + 1]  = interpy
                data[arrIndex + 2]  = 0.0
                data[arrIndex + 3]  = 0.0
            }
        }
    }
    
    lutTexture.replace(region: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                       mipmapLevel: 0,
                       withBytes: data,
                       bytesPerRow: bytesPerRow)
}
*/
