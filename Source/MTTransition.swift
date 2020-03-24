//
//  MTTransition.swift
//  MTTransitions
//
//  Created by xu.shuifeng on 2019/1/24.
//

import Foundation
import MetalPetal

/// The callback when transition updated
public typealias MTTransitionUpdater = (_ image: MTIImage) -> Void

/// The callback when transition completed
public typealias MTTransitionCompletion = (_ finished: Bool) -> Void

public class MTTransition: NSObject, MTIUnaryFilter {
    
    public override init() { }

    public var inputImage: MTIImage?

    public var destImage: MTIImage?
    
    public var outputPixelFormat: MTLPixelFormat = .invalid
    
    public var progress: Float = 0.0
    
    public var duration: TimeInterval = 1.2
    
    var completion: MTTransitionCompletion?
    
    private var updater: MTTransitionUpdater?
    private weak var driver: CADisplayLink?
    private var startTime: TimeInterval?
    
    // Subclasses must provide fragmentName
    var fragmentName: String { return "" }
    var parameters: [String: Any] { return [:] }
    var samplers: [String: String] { return [:] }
    
    public var outputImage: MTIImage? {
        guard let input = inputImage, let dest = destImage else {
            return inputImage
        }
        var images: [MTIImage] = [input, dest]
        let outputDescriptors = [ MTIRenderPassOutputDescriptor(dimensions: MTITextureDimensions(cgSize: input.size), pixelFormat: outputPixelFormat)]
        
        for key in samplers.keys {
            let name = samplers[key]!
            images.append(samplerImage(name: name)!)
        }
        
        var params = parameters
        params["ratio"] = Float(input.size.width / input.size.height)
        params["progress"] = progress
        
        let output = kernel.apply(toInputImages: images, parameters: params, outputDescriptors: outputDescriptors).first
        return output
    }
    
    var kernel: MTIRenderPipelineKernel {
        let vertexDescriptor = MTIFunctionDescriptor(name: MTIFilterPassthroughVertexFunctionName)
        let fragmentDescriptor = MTIFunctionDescriptor(name: fragmentName, libraryURL: MTIDefaultLibraryURLForBundle(Bundle(for: MTTransition.self)))
        let kernel = MTIRenderPipelineKernel(vertexFunctionDescriptor: vertexDescriptor, fragmentFunctionDescriptor: fragmentDescriptor)
        return kernel
    }
    
    private func samplerImage(name: String) -> MTIImage? {
        let bundle = Bundle(for: MTTransition.self)
        let bundleUrl = bundle.url(forResource: "Assets", withExtension: "bundle")!
        let resourceBundle = Bundle(url: bundleUrl)!
        
        if let imageUrl = resourceBundle.url(forResource: name, withExtension: nil) {
            let ciImage = CIImage(contentsOf: imageUrl)
            return MTIImage(ciImage: ciImage!, isOpaque: true)
        }
        return nil
    }
    
    public func transition(from fromImage: MTIImage, to toImage: MTIImage, updater: @escaping MTTransitionUpdater, completion: MTTransitionCompletion?) {
        self.inputImage = fromImage
        self.destImage = toImage
        self.updater = updater
        self.completion = completion
        self.startTime = nil
        let driver = CADisplayLink(target: self, selector: #selector(render(sender:)))
        driver.add(to: .main, forMode: .common)
        driver.add(to: .main, forMode: .tracking)
        self.driver = driver
    }
    
    @objc private func render(sender: CADisplayLink) {
        let startTime: CFTimeInterval
        if let time = self.startTime {
            startTime = time
        } else {
            startTime = sender.timestamp
            self.startTime = startTime
        }
        
        let progress = (sender.timestamp - startTime) / duration
        if progress > 1 {
            self.progress = 1.0
            if let image = outputImage {
                self.updater?(image)
            }
            self.driver?.invalidate()
            self.driver = nil
            self.updater = nil
            self.completion?(true)
            self.completion = nil
            return
        }
        
        self.progress = Float(progress)
        if let image = outputImage {
            self.updater?(image)
        }
    }
    
    public func cancel() {
        self.completion?(false)
    }
}