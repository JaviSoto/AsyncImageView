//
//  ImageProcessingRenderer.swift
//  AsyncImageView
//
//  Created by Nacho Soto on 11/27/15.
//  Copyright © 2015 Nacho Soto. All rights reserved.
//

import UIKit
import ReactiveCocoa

/// `RendererType` decorator that applies processing to every emitted image.
public final class ImageProcessingRenderer<Renderer: RendererType>: RendererType {
	public typealias Block = (image: UIImage, data: Renderer.Data) -> UIImage

	private let renderer: Renderer
	private let processingBlock: Block

	public init(renderer: Renderer, processingBlock: Block) {
		self.renderer = renderer
		self.processingBlock = processingBlock
	}

	public func renderImageWithData(data: Renderer.Data) -> SignalProducer<UIImage, Renderer.Error> {
		return self.renderer.renderImageWithData(data)
			.observeOn(QueueScheduler())
			.map { $0.image }
			.map { [block = self.processingBlock] image in
				block(image: image, data: data)
			}
	}
}

extension RendererType {
	/// Decorates this `RendererType` by applying the given block to every generated image.
	public func processedWithBlock(block: ImageProcessingRenderer<Self>.Block) -> ImageProcessingRenderer<Self> {
		return ImageProcessingRenderer(renderer: self, processingBlock: block)
	}
}
