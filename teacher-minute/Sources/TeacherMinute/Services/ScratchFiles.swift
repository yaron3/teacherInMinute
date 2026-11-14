//
//  ScratchFiles.swift
//  TeacherMinute
//
//  Where the app keeps files it can rebuild: the caches directory.
//
//  Not `FileManager.default.temporaryDirectory`: on Android that resolves to a
//  folder the app may not write to, so every write there fails with "You don't
//  have permission" (IT-24, a picked photo's preview drawn black).
//

import Foundation

enum ScratchFiles {
  /// `name` inside the caches directory, created if missing.
  static func directory(_ name: String) -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directory = base.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
