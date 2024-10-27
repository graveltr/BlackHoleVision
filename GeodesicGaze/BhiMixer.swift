//
//  BhiMixer.swift
//  MultiCamDemo
//
//  Created by Trevor Gravely on 7/16/24.
//

import MetalKit

class BhiMixer {
    
    struct Uniforms {
        var frontTextureWidth: Int32
        var frontTextureHeight: Int32
        var backTextureWidth: Int32
        var backTextureHeight: Int32
        var mode: Int32
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
    }

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var precomputeCommandQueue: MTLCommandQueue!
    var textureCache: CVMetalTextureCache!
    var pipelineState: MTLRenderPipelineState!
    var computePipelineState: MTLComputePipelineState!
    var postProcessingPipelineState: MTLComputePipelineState!
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
    
    var filterParameters = FilterParameters(spaceTimeMode: 0, sourceMode: 1, d: 0, a: 0, thetas: 0)
    var needsNewLutTexture = true
    
    var filterParametersBuffer: MTLBuffer
    var uniformsBuffer: MTLBuffer
    var widthBuffer: MTLBuffer
    var debugMatrixBuffer: MTLBuffer?
    
    var totalElements: Int = 0
    var debugMatrixWidth: Int = 0
    var debugMatrixHeight: Int = 0

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.precomputeCommandQueue = device.makeCommandQueue()
        self.mode = 0
        
        self.filterParametersBuffer = device.makeBuffer(length: MemoryLayout<FilterParameters>.size, options: .storageModeShared)!
        self.uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)!
        self.widthBuffer = device.makeBuffer(length: MemoryLayout<UInt>.size, options: .storageModeShared)!
        
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        
        setupPipelines()
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
        
        let postProcessingFunction = library?.makeFunction(name: "postProcess")
        postProcessingPipelineState = try! device.makeComputePipelineState(function: postProcessingFunction!)
    }
    
    func initializeSizeDependentData(width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        lutTexture = device.makeTexture(descriptor: descriptor)
        
        debugMatrixWidth = lutTexture.width;
        debugMatrixHeight = lutTexture.height;
        totalElements = debugMatrixWidth * debugMatrixHeight;
        let debugMatrixBufferSize = totalElements * MemoryLayout<simd_float3>.stride;
        
        debugMatrixBuffer = device.makeBuffer(length: debugMatrixBufferSize, options: .storageModeShared)
        
        var matrixWidth = debugMatrixWidth
        memcpy(widthBuffer.contents(), &matrixWidth, MemoryLayout<UInt>.size)
    }
    
    func mix(frontCameraPixelBuffer: CVPixelBuffer?,
             backCameraPixelBuffer: CVPixelBuffer?,
             in view: MTKView) {
        
        guard let drawable = view.currentDrawable else {
            print("Currentdrawable is nil")
            return
        }
        
        if needsNewLutTexture {
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

            computeCommandBuffer.commit()
            computeCommandBuffer.waitUntilCompleted()
            
            if filterParameters.spaceTimeMode == 2 && filterParameters.sourceMode == 0 {
                // cpuPostProcess(rowInterp: fEqual(0.01, filterParameters.a))
                cpuPostProcessStatic()
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
              let backTextureHeight = backTextureHeight else {
            print("returning from mix")
            return
        }
        
        var uniforms = Uniforms(frontTextureWidth: Int32(frontTextureWidth), 
                                frontTextureHeight: Int32(frontTextureHeight),
                                backTextureWidth: Int32(backTextureWidth),
                                backTextureHeight: Int32(backTextureHeight),
                                mode: filterParameters.sourceMode)
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
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        renderCommandBuffer.present(drawable)
        renderCommandBuffer.commit()
        renderCommandBuffer.waitUntilCompleted()
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
    
    private func cpuPostProcessStatic() {
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
        
        let seekWidth = 70
        let startRow = textureHeight / 2 - seekWidth / 2
        let endRow = textureHeight / 2 + seekWidth / 2
        
        let combinedRange = Array(0..<startCol) + Array(endCol..<textureWidth)

        for col in combinedRange {
            
            let arrIdxOfStartPixel = rowColToArrIdx(row: startRow, col: col, width: textureWidth)
            let arrIdxOfEndPixel = rowColToArrIdx(row: endRow, col: col, width: textureWidth)
            
            let startPixelx = data[arrIdxOfStartPixel]
            let startPixely = data[arrIdxOfStartPixel + 1]
            
            let endPixelx = data[arrIdxOfEndPixel]
            let endPixely = data[arrIdxOfEndPixel + 1]

            for row in startRow...endRow {
                let arrIndex = rowColToArrIdx(row: row, col: col, width: textureWidth)
                
                let factor: Float = Float(row - startRow) / Float(endRow - startRow + 1)
                
                let interpx = mix(startPixelx, endPixelx, factor)
                let interpy = mix(startPixely, endPixely, factor)
                
                data[arrIndex]      = interpx
                data[arrIndex + 1]  = interpy
                data[arrIndex + 2]  = 0.0
                data[arrIndex + 3]  = 0.0
            }
        }
        
        lutTexture.replace(region: MTLRegionMake2D(0, 0, textureWidth, textureHeight),
                           mipmapLevel: 0,
                           withBytes: data,
                           bytesPerRow: bytesPerRow)
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
