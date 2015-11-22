//
//  ImageProvider.swift
//  ChessWatchApp
//
//  Created by Nacho Soto on 9/17/15.
//  Copyright © 2015 Javier Soto. All rights reserved.
//

import Foundation
import ReactiveCocoa

public protocol ImageProviderType {
	typealias RenderData: RenderDataType

	func getImageForData(data: RenderData) -> SignalProducer<RenderResult, NoError>
}
