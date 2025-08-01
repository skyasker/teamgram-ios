import Foundation
import SwiftSignalKit

private final class TempBoxFileContext {
    let directory: String
    let fileName: String
    var subscribers = Set<Int>()
    
    var path: String {
        if self.fileName.isEmpty {
            return self.directory
        } else {
            return self.directory + "/" + self.fileName
        }
    }
    
    init(directory: String, fileName: String) {
        self.directory = directory
        self.fileName = fileName
    }
}

private struct TempBoxKey: Equatable, Hashable {
    let path: String?
    let fileName: String
    let uniqueId: Int?
}

public final class TempBoxFile {
    fileprivate let key: TempBoxKey
    fileprivate let id: Int
    public let path: String
    
    fileprivate init(key: TempBoxKey, id: Int, path: String) {
        self.key = key
        self.id = id
        self.path = path
    }
}

public final class TempBoxDirectory {
    fileprivate let key: TempBoxKey
    fileprivate let id: Int
    public let path: String
    
    fileprivate init(key: TempBoxKey, id: Int, path: String) {
        self.key = key
        self.id = id
        self.path = path
    }
}

private final class TempBoxContexts {
    private var nextId: Int = 0
    private var contexts: [TempBoxKey: TempBoxFileContext] = [:]
    
    func file(basePath: String, path: String, fileName: String) -> TempBoxFile {
        let key = TempBoxKey(path: path, fileName: fileName, uniqueId: nil)
        let context: TempBoxFileContext
        if let current = self.contexts[key] {
            context = current
        } else {
            let id = self.nextId
            self.nextId += 1
            let dirName = "\(id)"
            let dirPath = basePath + "/" + dirName
            var cleanName = fileName
            if cleanName.hasPrefix("..") {
                cleanName = "__" + String(cleanName[cleanName.index(cleanName.startIndex, offsetBy: 2)])
            }
            cleanName = cleanName.replacingOccurrences(of: "/", with: "_")
            context = TempBoxFileContext(directory: dirPath, fileName: cleanName)
            self.contexts[key] = context
            let _ = try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: nil)
            let _ = try? FileManager.default.linkItem(atPath: path, toPath: context.path)
        }
        let id = self.nextId
        self.nextId += 1
        context.subscribers.insert(id)
        return TempBoxFile(key: key, id: id, path: context.path)
    }
    
    func tempFile(basePath: String, fileName: String) -> TempBoxFile {
        let id = self.nextId
        self.nextId += 1
        
        let key = TempBoxKey(path: nil, fileName: fileName, uniqueId: id)
        let context: TempBoxFileContext
        
        let dirName = "\(id)"
        let dirPath = basePath + "/" + dirName
        var cleanName = fileName
        if cleanName.hasPrefix("..") {
            cleanName = "__" + String(cleanName[cleanName.index(cleanName.startIndex, offsetBy: 2)])
        }
        cleanName = cleanName.replacingOccurrences(of: "/", with: "_")
        context = TempBoxFileContext(directory: dirPath, fileName: cleanName)
        self.contexts[key] = context
        let _ = try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: nil)
    
        context.subscribers.insert(id)
        return TempBoxFile(key: key, id: id, path: context.path)
    }
    
    func tempDirectory(basePath: String) -> TempBoxDirectory {
        let id = self.nextId
        self.nextId += 1
        
        let key = TempBoxKey(path: nil, fileName: "", uniqueId: id)
        let context: TempBoxFileContext
        
        let dirName = "\(id)"
        let dirPath = basePath + "/" + dirName
        context = TempBoxFileContext(directory: dirPath, fileName: "")
        self.contexts[key] = context
        let _ = try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: nil)
    
        context.subscribers.insert(id)
        return TempBoxDirectory(key: key, id: id, path: context.path)
    }
    
    func dispose(_ file: TempBoxFile) -> [String] {
        if let context = self.contexts[file.key] {
            context.subscribers.remove(file.id)
            if context.subscribers.isEmpty {
                self.contexts.removeValue(forKey: file.key)
                return [context.directory]
            }
        }
        return []
    }
    
    func dispose(_ directory: TempBoxDirectory) -> [String] {
        if let context = self.contexts[directory.key] {
            context.subscribers.remove(directory.id)
            if context.subscribers.isEmpty {
                self.contexts.removeValue(forKey: directory.key)
                return [context.directory]
            }
        }
        return []
    }
}

private var sharedValue: TempBox?
public final class TempBox {
    // 基础路径
    private let basePath: String
    // 进程类型
    private let processType: String
    // 启动特定ID
    private let launchSpecificId: Int64
    // 当前基础路径
    private let currentBasePath: String
    
    // 使用原子操作管理临时文件上下文
    private let contexts = Atomic<TempBoxContexts>(value: TempBoxContexts())
    
    /// 初始化共享的TempBox实例
    /// - Parameters:
    ///   - basePath: 基础路径
    ///   - processType: 进程类型
    ///   - launchSpecificId: 启动特定ID
    public static func initializeShared(basePath: String, processType: String, launchSpecificId: Int64) {
        sharedValue = TempBox(basePath: basePath, processType: processType, launchSpecificId: launchSpecificId)
    }
    
    /// 获取共享的TempBox实例
    public static var shared: TempBox {
        return sharedValue!
    }
    
    /// 私有初始化方法
    /// - Parameters:
    ///   - basePath: 基础路径
    ///   - processType: 进程类型
    ///   - launchSpecificId: 启动特定ID
    private init(basePath: String, processType: String, launchSpecificId: Int64) {
        self.basePath = basePath
        self.processType = processType
        self.launchSpecificId = launchSpecificId
        
        // 创建当前基础路径
        self.currentBasePath = basePath + "/temp/" + processType + "/temp-" + String(UInt64(bitPattern: launchSpecificId), radix: 16)
        // 清理之前启动的临时文件
        self.cleanupPreviousLaunches(path: basePath + "/temp/" + processType, currentLaunchSpecificId: launchSpecificId)
    }
    
    /// 清理之前启动产生的临时文件
    /// - Parameters:
    ///   - path: 临时文件路径
    ///   - currentLaunchSpecificId: 当前启动ID
    private func cleanupPreviousLaunches(path: String, currentLaunchSpecificId: Int64) {
        DispatchQueue.global(qos: .background).async {
            let currentName = "temp-" + String(UInt64(bitPattern: currentLaunchSpecificId), radix: 16)
            if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [], options: []) {
                for url in files {
                    if url.lastPathComponent.hasPrefix("temp-") && url.lastPathComponent != currentName {
                        let _ = try? FileManager.default.removeItem(atPath: url.path)
                    }
                }
            }
        }
    }
    
    /// 根据已有文件路径创建临时文件
    /// - Parameters:
    ///   - path: 源文件路径
    ///   - fileName: 文件名
    /// - Returns: 临时文件对象
    public func file(path: String, fileName: String) -> TempBoxFile {
        return self.contexts.with { contexts in
            return contexts.file(basePath: self.currentBasePath, path: path, fileName: fileName)
        }
    }
    
    /// 创建新的临时文件
    /// - Parameter fileName: 文件名
    /// - Returns: 临时文件对象
    public func tempFile(fileName: String) -> TempBoxFile {
        return self.contexts.with { contexts in
            return contexts.tempFile(basePath: self.currentBasePath, fileName: fileName)
        }
    }
    
    /// 创建临时目录
    /// - Returns: 临时目录对象
    public func tempDirectory() -> TempBoxDirectory {
        return self.contexts.with { contexts in
            return contexts.tempDirectory(basePath: self.currentBasePath)
        }
    }
    
    /// 释放临时文件
    /// - Parameter file: 要释放的临时文件
    public func dispose(_ file: TempBoxFile) {
        let removePaths = self.contexts.with { contexts in
            return contexts.dispose(file)
        }
        if !removePaths.isEmpty {
            DispatchQueue.global(qos: .background).async {
                for path in removePaths {
                    let _ = try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
    }
    
    /// 释放临时目录
    /// - Parameter directory: 要释放的临时目录
    public func dispose(_ directory: TempBoxDirectory) {
        let removePaths = self.contexts.with { contexts in
            return contexts.dispose(directory)
        }
        if !removePaths.isEmpty {
            DispatchQueue.global(qos: .background).async {
                for path in removePaths {
                    let _ = try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
    }
}
