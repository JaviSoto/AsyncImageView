//
//  Caching.swift
//  AsyncImageView
//
//  Created by Nacho Soto on 9/17/15.
//  Copyright © 2015 Nacho Soto. All rights reserved.
//

import Foundation

public protocol CacheType {
	associatedtype Key
	associatedtype Value

	/// Retrieves the value for this key.
	func valueForKey(_ key: Key) -> Value?
    
    /// Sets a value for a key. If `value` is `nil`, it will be removed.
    func setValue(_ value: Value?, forKey key: Key)

	/// Sets a value for a key. If `value` is `nil`, it will be removed.
	func setValue(_ value: Value?, forKey key: Key, expiration: CacheExpiration)
}

public enum CacheExpiration {
    case seconds(TimeInterval)
    case days(Int)
    case date(Date)
    case never
}

// MARK: -

/// `CacheType` backed by `NSCache`.
public final class InMemoryCache<K: Hashable, V>: CacheType {
	private typealias NativeCacheType = NSCache<CacheKey<K>, CacheValue<V>>

	private let cache: NativeCacheType

	public init(cacheName: String) {
		self.cache = NativeCacheType()
		self.cache.name = cacheName
	}

	public func valueForKey(_ key: K) -> V? {
        if let value = cache.object(forKey: CacheKey<K>(value: key)), !value.isExpired {
            return value.wrapped
        } else {
            return nil
        }
	}

    public func setValue(_ value: V?, forKey key: K) {
        self.setValue(value, forKey: key, expiration: .never)
    }
    
    public func setValue(_ value: V?, forKey key: K, expiration: CacheExpiration) {
		let key = CacheKey(value: key)

        if let value = value {
			cache.setObject(CacheValue(wrapped: value, expirationDate: expiration.date), forKey: key)
		} else {
			cache.removeObject(forKey: key)
		}
	}
}

private class CacheValue<V>: NSObject {
	let wrapped: V
    let expirationDate: Date

	init(wrapped: V, expirationDate: Date) {
		self.wrapped = wrapped
        self.expirationDate = expirationDate
	}
    
    var isExpired: Bool {
        return self.expirationDate.inThePast
    }
}

private enum DiskCacheValueKeys: String {
    case value
    case expiration
}

private final class DiskCacheValue<V: NSDataConvertible>: CacheValue<V> {
    override init(wrapped: V, expirationDate: Date) {
        super.init(wrapped: wrapped, expirationDate: expirationDate)
    }
    
    required init?(coder aDecoder: NSCoder) {
        guard let value = aDecoder.decodeObject(forKey: DiskCacheValueKeys.value.rawValue) as? V,
            let expiration = aDecoder.decodeObject(forKey: DiskCacheValueKeys.expiration.rawValue) as! Date? else {
                return nil
        }
        
        super.init(wrapped: value, expirationDate: expiration)
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(self.wrapped, forKey: DiskCacheValueKeys.value.rawValue)
        aCoder.encode(self.expirationDate, forKey: DiskCacheValueKeys.expiration.rawValue)
    }
}

private final class CacheKey<K: Hashable>: NSObject {
	private let value: K
	private let cachedHash: Int

	init(value: K) {
		self.value = value
		self.cachedHash = value.hashValue

		super.init()
	}

	@objc override func isEqual(_ object: Any?) -> Bool {
		if let otherData = object as? CacheKey<K> {
			return otherData.value == self.value
		} else {
			return false
		}
	}

	@objc override var hash: Int {
		return self.cachedHash
	}
}

// MARK: -

/// Represents the key for a value that can be persisted on disk.
public protocol DataFileType {
	/// Optionally provide a subdirectory for this value.
	var subdirectory: String? { get }

	/// The string that can uniquely reference this value.
	var uniqueFilename: String { get }
}

/// Represents a value that can be persisted on disk.
public protocol NSDataConvertible {
	/// Creates an instance of the receiver from `NSData`, if possible.
	init?(data: Data)

	/// Encodes the receiver in `NSData`. Returns `nil` if failed.
	var data: Data? { get }
}

/// Returns the directory where all `DiskCache` caches are stored
/// by default.
public func diskCacheDefaultCacheDirectory() -> URL {
	return try! FileManager()
		.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		.appendingPathComponent("AsyncImageView", isDirectory: true)
}

/// `CacheType` backed by files on disk.
public final class DiskCache<K: DataFileType, V: NSDataConvertible>: CacheType {
	private let rootDirectory: URL
	private let fileManager = FileManager.default
	private let lock: NSLock

	public static func onCacheSubdirectory(_ directoryName: String) -> DiskCache {
		let url = diskCacheDefaultCacheDirectory()
			.appendingPathComponent(directoryName, isDirectory: true)

		return DiskCache(rootDirectory: url)
	}

	public init(rootDirectory: URL) {
		self.rootDirectory = rootDirectory
		self.lock = NSLock()
		self.lock.name = "DiskCache.\(rootDirectory.absoluteString)"
	}

	public func valueForKey(_ key: K) -> V? {
        let path = self.filePathForKey(key).absoluteString
        
        return withLock {
            if self.fileManager.fileExists(atPath: path),
                let value = NSKeyedUnarchiver.unarchiveObject(withFile: path) as! DiskCacheValue<V>?,
                !value.isExpired {
                return value.wrapped
            } else {
                return nil
            }
        }
	}
    
    public func setValue(_ value: V?, forKey key: K) {
        self.setValue(value, forKey: key, expiration: .never)
    }

	public func setValue(_ value: V?, forKey key: K, expiration: CacheExpiration) {
        let url = self.filePathForKey(key)
		let path = url.absoluteString

		self.withLock {
			self.guaranteeDirectoryExists(url.deletingLastPathComponent())
            
            let data = value
                .map { DiskCacheValue(wrapped: $0, expirationDate: expiration.date) }
            
            if let data = data {
                NSKeyedArchiver.archiveRootObject(data, toFile: path)
			} else if self.fileManager.fileExists(atPath: path) {
				try! self.fileManager.removeItem(at: url)
			}
		}
	}

	private func withLock<T>(_ block: () -> T) -> T {
		self.lock.lock()
		let result = block()
		self.lock.unlock()

		return result
	}

	private func filePathForKey(_ key: K) -> URL {
		if let subdirectory = key.subdirectory {
			return self.rootDirectory
				.appendingPathComponent(subdirectory, isDirectory: true)
				.appendingPathComponent(key.uniqueFilename, isDirectory: false)
		} else {
			return self.rootDirectory
				.appendingPathComponent(key.uniqueFilename, isDirectory: false)
		}
	}

	private func guaranteeDirectoryExists(_ url: URL) {
		try! self.fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
	}
}

fileprivate extension CacheExpiration {
    var date: Date {
        switch self {
        case let .seconds(seconds):
            return Date().addingTimeInterval(seconds)
        case let .days(days):
            return Date().addingTimeInterval(Double(days) * 86400.0)
        case let .date(date):
            return date
        case .never:
            return Date.distantFuture
        }
    }
}

fileprivate extension Date {
    var inThePast: Bool {
        return self.timeIntervalSinceNow < 0
    }
}
