import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift read-release-manifest.swift manifest.json key\n", stderr)
    exit(2)
}

do {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let key = CommandLine.arguments[2]
    guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
          let value = object[key]
    else {
        throw NSError(
            domain: "SidekinRelease",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Manifest is invalid or is missing key '\(key)'."]
        )
    }
    if let text = value as? String {
        print(text)
    } else if let number = value as? NSNumber {
        print(number.stringValue)
    } else {
        throw NSError(
            domain: "SidekinRelease",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Manifest key '\(key)' is not a scalar value."]
        )
    }
} catch {
    fputs("Manifest read failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
