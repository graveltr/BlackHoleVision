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
    
    var filterParameters = FilterParameters(spaceTimeMode: 2, sourceMode: 1, d: 0, a: 0, thetas: 0)
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
            
            computeCommandBuffer.commit()
            computeCommandBuffer.waitUntilCompleted()
            
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
}
