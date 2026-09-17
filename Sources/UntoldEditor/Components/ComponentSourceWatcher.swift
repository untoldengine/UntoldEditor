//
//  ComponentSourceWatcher.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreServices
import Foundation

/// Watches source folders and reports when a `.swift` file changes, is added or goes away.
///
/// FSEvents rather than a directory descriptor: a descriptor on the folder does not fire when
/// an existing file is rewritten in place.
final class ComponentSourceWatcher {
    private let directories: [URL]
    private let latency: TimeInterval
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    init(directories: [URL], latency: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        self.directories = directories
        self.latency = latency
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, directories.isEmpty == false else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            let watcher = Unmanaged<ComponentSourceWatcher>.fromOpaque(info).takeUnretainedValue()
            if paths.prefix(count).contains(where: { $0.hasSuffix(".swift") }) {
                watcher.onChange()
            }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            directories.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
