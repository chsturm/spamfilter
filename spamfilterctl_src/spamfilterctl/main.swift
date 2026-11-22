//
//  main.swift
//  spamfilterctl
//
//  Created by Christian Sturm on 05.11.26.
//

import Foundation
import OSAKit

let scriptURL = URL.libraryDirectory.appending(path: "Application Scripts/com.apple.mail/spamfilter.scpt", directoryHint: .notDirectory)
#if DEBUG
print("Run spamfilterctl helper")
print(scriptURL)
#endif

var error: NSDictionary? = nil
let script = OSAScript(contentsOf: scriptURL, error: &error)
if error != nil || script == nil {
    fatalError("Could not load script from \(scriptURL.path): \(error?.description ?? "No error")")
}

var displayValue: NSAttributedString? = nil
var errorInfo: NSDictionary? = nil
let appleEventDescriptor = script?.executeAndReturnDisplayValue(&displayValue,
                                                                error: &errorInfo)
#if DEBUG
print("display value: \(displayValue?.string ?? "No display value")")
print("event result: \(appleEventDescriptor?.description ?? "No event result")")
#endif

if let errorInfo = errorInfo {
    fatalError("Script error: \(errorInfo.description)")
}
