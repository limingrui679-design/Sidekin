import CoreGraphics
import Foundation

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] else {
    exit(1)
}

let requestedPID = CommandLine.arguments.dropFirst().first.flatMap(Int.init)

for window in windows {
    guard let owner = window[kCGWindowOwnerName as String] as? String,
          let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
          let number = window[kCGWindowNumber as String] as? Int,
          let layer = window[kCGWindowLayer as String] as? Int,
          let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
    else { continue }

    let matches = requestedPID.map { $0 == ownerPID }
        ?? owner.localizedCaseInsensitiveContains("cainiao")
    guard matches else { continue }

    let name = window[kCGWindowName as String] as? String ?? ""
    print(
        "\(number)|\(ownerPID)|\(owner)|\(layer)|"
            + String(format: "%.0f,%.0f,%.0f,%.0f", bounds.origin.x, bounds.origin.y, bounds.width, bounds.height)
            + "|\(name)"
    )
}
