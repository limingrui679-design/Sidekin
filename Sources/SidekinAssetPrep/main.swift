import SidekinCreator
import Foundation

guard CommandLine.arguments.count >= 3,
      CommandLine.arguments.count.isMultiple(of: 2) == false
else {
    fputs(
        "Usage: swift run SidekinAssetPrep input.png output.png [input output ...]\n",
        stderr
    )
    exit(2)
}

do {
    var index = 1
    while index < CommandLine.arguments.count {
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[index])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let source = try Data(contentsOf: inputURL)
        let prepared = try PetImageProcessor.prepareGeneratedAsset(
            source,
            removeEnclosedBackground: true
        )
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try prepared.write(to: outputURL, options: .atomic)
        print("Prepared \(outputURL.lastPathComponent)")
        index += 2
    }
} catch {
    fputs("Asset preparation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
