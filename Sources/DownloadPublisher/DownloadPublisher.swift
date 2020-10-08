//
//  File.swift
//
//
//  Created by Cenk Bilgen on 2020-10-08.
//

import Foundation
import Combine

enum OverwritePolicy { case keep, overwrite, rename }

class Downloader {
  
  let session: URLSession
  let delegate: DownloadDelegate
  
  var cancellables: Set<AnyCancellable> = []
  
  class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var tasks: [Int: (URL, OverwritePolicy)] = [:]
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
      defer  {
        tasks.removeValue(forKey: downloadTask.taskIdentifier)
      }
      guard let (saveURL, overwritePolicy) = tasks[downloadTask.taskIdentifier] else {
        print("No save location specified for task \(downloadTask.taskIdentifier)")
        return
      }
      do {
        var isDirectory: ObjCBool = false // yup, still
        let fileExists = FileManager.default.fileExists(atPath: saveURL.path, isDirectory: &isDirectory)
        switch overwritePolicy {
          case .keep:
            if fileExists == false {
              try FileManager.default.moveItem(at: location, to: saveURL)
            }
          case .overwrite:
            if fileExists && isDirectory.boolValue == false {
              try FileManager.default.removeItem(at: saveURL)
            }
            try FileManager.default.moveItem(at: location, to: saveURL)
          case .rename:
            if fileExists && isDirectory.boolValue == false {
              let ext = saveURL.pathExtension
              let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".unicodeScalars
              let newFilename = (0...6).reduce("-") { (string, _) in
                string.appending(String(chars.randomElement()!))
              }
              let renamedURL = saveURL.deletingLastPathComponent().appendingPathComponent(newFilename).appendingPathExtension(ext)
              try FileManager.default.moveItem(at: location, to: renamedURL)
            } else {
              try FileManager.default.moveItem(at: location, to: saveURL)
            }
        }
        print("Downloaded file saved to \(saveURL.absoluteString)")
      } catch {
        print("Error moving to save url \(saveURL.absoluteString). \(error)")
      }
    }
  }
  
  init() {
    self.delegate = DownloadDelegate()
    let configuration = URLSessionConfiguration.ephemeral
    let queue = OperationQueue()
    queue.name = "downloadSessionQueue"
    self.session = URLSession(configuration: configuration, delegate: self.delegate, delegateQueue: queue)
  }
  
  // if you want progress and specifying location
  
  func download(from: URL, to: URL) -> AnyPublisher<(URLRequest, URLResponse?, Progress), Error> {
    let task = session.downloadTask(with: from)
    let publisher = Publishers.CombineLatest4(
      task.publisher(for: \.currentRequest, options: .initial),
      task.publisher(for: \.response),
      task.publisher(for: \.progress),
      task.publisher(for: \.error))
      .tryMap { (request, response, progress, error) -> (URLRequest, URLResponse?, Progress) in
        if error != nil {
          throw error!
        } else if request == nil {
          throw URLError(.unknown)
        } else {
          return (request!, response, progress)
        }
      }
    
    delegate.tasks[task.taskIdentifier] = (to, .rename)
    task.resume()
    return publisher.eraseToAnyPublisher()
  }
  
  // if you dont' care about progress or specifying location
  // just the task state and the completed data
  
  func download(with request: URLRequest) -> Future<Data, Error> {
    let task = session.downloadTask(with: request)
    let url = generateTempCacheURL()
    delegate.tasks[task.taskIdentifier] = (url, .overwrite)
    
    let publisher = Future<Data, Error> { (promise) in
      task.publisher(for: \.state, options: .initial)
        .combineLatest(task.publisher(for: \.error))
        .sink { (completion) in
          if case .failure(let error) = completion {
            promise(.failure(error))
          }
        } receiveValue: { (state, _) in
          guard state == .completed else { return }
          do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            promise(.success(data))
          } catch {
            promise(.failure(error))
          }
         
        }
        .store(in: &self.cancellables)
    }
    return publisher
  }
  
  private func generateTempCacheURL() -> URL {
    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".unicodeScalars
    let filename = (0...8).reduce("") { (string, _) in
      string.appending(String(chars.randomElement()!))
    }
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent(filename)
  }
  
}
