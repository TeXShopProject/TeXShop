// Write the year of the build into the copyright of the built application's About panel.
//
// The About text reads "© 2001–2026 Richard Koch" and "© 2026 Yusuke Terada". Richard Koch handed
// TeXShop over in 2026, so his years stay as they are; the current developer's years run to the
// year of the build ("© 2026–2027 Yusuke Terada"). Only the built bundle changes, before it is
// signed; the sources keep the years as written.
//
// Usage: update-copyright-year.swift <path of the built .app>
// TEXSHOP_COPYRIGHT_YEAR replaces the current year (for Tests/run-copyright-year.py).
import Foundation

let bundle = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
let year = ProcessInfo.processInfo.environment["TEXSHOP_COPYRIGHT_YEAR"].flatMap { Int($0) }
    ?? calendar.component(.year, from: Date())
let firstYear = 2026
let currentDeveloper = try NSRegularExpression(pattern: #"(?<=\#(firstYear))(?:[-–][0-9]{4})?(?= Yusuke Terada)"#)
let ending = year > firstYear ? "–\(year)" : ""

let resources = bundle.appendingPathComponent("Contents/Resources")
var files = [bundle.appendingPathComponent("Contents/Info.plist")]
for directory in try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
where directory.pathExtension == "lproj" {
    let file = directory.appendingPathComponent("InfoPlist.strings")
    if FileManager.default.fileExists(atPath: file.path) { files.append(file) }
}
var updated = 0
for file in files {
    var format = PropertyListSerialization.PropertyListFormat.binary
    guard var values = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: &format) as? [String: Any] else {
        fatalError("Invalid property list: \(file.path)")
    }
    var changed = false
    for key in ["CFBundleGetInfoString", "NSHumanReadableCopyright"] {
        guard let text = values[key] as? String else { continue }
        let replacement = currentDeveloper.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ending)
        if replacement != text { values[key] = replacement; changed = true }
    }
    if changed {
        // Property lists cannot be written in the old text format; the built strings files are binary anyway.
        let outputFormat: PropertyListSerialization.PropertyListFormat = format == .openStep ? .binary : format
        try PropertyListSerialization.data(fromPropertyList: values, format: outputFormat, options: 0).write(to: file, options: .atomic)
        updated += 1
    }
}
print("About copyright of the current developer runs to \(year); updated \(updated) files")

// A declared output of this always-run phase makes Xcode sign the bundle again afterwards,
// also in incremental builds that cross the turn of a year.
try "\(year)\n".write(to: resources.appendingPathComponent("BuildCopyrightYear.txt"), atomically: true, encoding: .utf8)
