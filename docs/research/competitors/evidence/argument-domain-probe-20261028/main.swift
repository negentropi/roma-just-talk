import Foundation
let raw = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["selectedAIProvider"]
let selected = UserDefaults.standard.string(forKey: "selectedAIProvider")
let report: [String: Any] = ["argumentRawType": raw.map { String(describing: type(of: $0)) } ?? "missing", "argumentRawValue": raw as Any? ?? NSNull(), "selectedValue": selected as Any? ?? NSNull(), "argvValue": CommandLine.arguments.last ?? "missing"]
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
