//
//  VideoDownloadManager.swift
//  Reynard
//
//  Created by Minh Ton on 23/11/26.
//

import Foundation

// MARK: - Download State

enum VideoDownloadState: Int {
    case waiting
    case downloading
    case paused
    case completed
    case failed
}

// MARK: - Download Item

final class VideoDownloadItem: NSObject {
    let id: String
    let sourceURL: URL
    let title: String
    var destinationURL: URL?
    var state: VideoDownloadState = .waiting
    var progress: Float = 0.0
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = 0
    var resumeData: Data?
    var task: URLSessionDownloadTask?

    init(url: URL, title: String) {
        self.id = UUID().uuidString
        self.sourceURL = url
        self.title = title
    }
}

// MARK: - Download Delegate

protocol VideoDownloadManagerDelegate: AnyObject {
    func downloadManager(_ manager: VideoDownloadManager, didUpdateProgress item: VideoDownloadItem)
    func downloadManager(_ manager: VideoDownloadManager, didComplete item: VideoDownloadItem, fileURL: URL?)
    func downloadManager(_ manager: VideoDownloadManager, didFail item: VideoDownloadItem, error: Error?)
}

// MARK: - Download Manager

/// URLSession-based background download manager with queue, resume, and file management.
final class VideoDownloadManager: NSObject {

    // MARK: - Singleton

    static let shared = VideoDownloadManager()

    // MARK: - Properties

    weak var delegate: VideoDownloadManagerDelegate?

    private let maxConcurrentDownloads = 3
    private var queue: [VideoDownloadItem] = []
    private var activeDownloads: [String: VideoDownloadItem] = []     // taskIdentifier -> item
    private var taskToItemMap: [Int: String] = []                     // URLSessionTask.taskIdentifier -> item.id

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.reynard.videoDownloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
    }

    // MARK: - Downloads Directory

    private var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ReynardDownloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Enqueue

    /// Adds a download to the queue and starts it if slots are available.
    @discardableResult
    func enqueue(url: URL, title: String) -> VideoDownloadItem {
        let item = VideoDownloadItem(url: url, title: title)
        queue.append(item)
        startNextIfNeeded()
        return item
    }

    // MARK: - Pause / Resume

    func pause(_ item: VideoDownloadItem) {
        guard item.state == .downloading, let task = item.task else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            item.resumeData = data
            item.state = .paused
            item.task = nil
            self?.delegate?.downloadManager(self!, didUpdateProgress: item)
        })
    }

    func resume(_ item: VideoDownloadItem) {
        guard item.state == .paused else { return }
        item.state = .waiting
        startItem(item)
    }

    // MARK: - Cancel

    func cancel(_ item: VideoDownloadItem) {
        item.task?.cancel()
        item.task = nil
        item.state = .failed
        removeFromActive(item)
        queue.removeAll { $0.id == item.id }
        startNextIfNeeded()
    }

    // MARK: - File Management

    /// Returns all successfully downloaded files.
    func listDownloadedFiles() -> [URL] {
        let dir = downloadsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: .skipsHiddenFiles
        )) ?? []
        return files
    }

    /// Deletes a downloaded file.
    func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func startNextIfNeeded() {
        while activeDownloads.count < maxConcurrentDownloads {
            guard let next = queue.first(where: { $0.state == .waiting }) else { break }
            startItem(next)
        }
    }

    private func startItem(_ item: VideoDownloadItem) {
        let task: URLSessionDownloadTask
        if let resumeData = item.resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: item.sourceURL)
        }

        item.task = task
        item.state = .downloading
        item.resumeData = nil
        activeDownloads[item.id] = item
        taskToItemMap[task.taskIdentifier] = item.id
        task.resume()
    }

    private func removeFromActive(_ item: VideoDownloadItem) {
        activeDownloads.removeValue(forKey: item.id)
        taskToItemMap = taskToItemMap.filter { $0.value != item.id }
    }

    private func item(for task: URLSessionTask) -> VideoDownloadItem? {
        guard let itemId = taskToItemMap[task.taskIdentifier] else { return nil }
        return activeDownloads[itemId] ?? queue.first(where: { $0.id == itemId })
    }
}

// MARK: - URLSessionDownloadDelegate

extension VideoDownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = item(for: downloadTask) else { return }

        // Build destination filename
        let ext = item.sourceURL.pathExtension.isEmpty ? "mp4" : item.sourceURL.pathExtension
        let safeName = item.title.replacingOccurrences(of: "[^a-zA-Z0-9_\\-]", with: "_", options: .regularExpression)
        let filename = "\(safeName)_\(item.id.prefix(8)).\(ext)"
        let destination = downloadsDirectory.appendingPathComponent(filename)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            item.destinationURL = destination
            item.state = .completed
            item.progress = 1.0
            removeFromActive(item)
            delegate?.downloadManager(self, didComplete: item, fileURL: destination)
        } catch {
            item.state = .failed
            removeFromActive(item)
            delegate?.downloadManager(self, didFail: item, error: error)
        }

        startNextIfNeeded()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let item = item(for: downloadTask) else { return }
        item.bytesReceived = totalBytesWritten
        item.totalBytes = totalBytesExpectedToWrite
        if totalBytesExpectedToWrite > 0 {
            item.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        }
        delegate?.downloadManager(self, didUpdateProgress: item)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = item(for: task), let error = error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled, let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeKey] as? Data {
            item.resumeData = resumeData
            item.state = .paused
        } else {
            item.state = .failed
            delegate?.downloadManager(self, didFail: item, error: error)
        }
        removeFromActive(item)
        startNextIfNeeded()
    }
}
