import Foundation
import Darwin

let value = "で コード です café \u{00E9} e\u{0301} 日本語 👩🏽‍💻"
let key = "RJT_UNICODE_TRANSPORT_PROBE"
func observe(_ id: String, executable: String, arguments: [String], environment: [String:String]?, input: Data? = nil) throws -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment { process.environment = environment }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    let inputPipe = Pipe()
    if input != nil { process.standardInput = inputPipe }
    try process.run()
    if let input {
        inputPipe.fileHandleForWriting.write(input)
        try inputPipe.fileHandleForWriting.close()
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let observed = String(decoding: data, as: UTF8.self)
    return ["id":id,"exitCode":process.terminationStatus,"expected":value,"observed":observed,
            "expectedUTF8":Array(value.utf8),"observedUTF8":Array(data),
            "expectedUTF16":Array(value.utf16),"observedUTF16":Array(observed.utf16),
            "UTF8Equal":data.elementsEqual(value.utf8),"UTF16Equal":observed.utf16.elementsEqual(value.utf16),
            "SwiftEqual":observed == value]
}
var observations: [[String:Any]] = []
let minimalEnvironment = [key:value, "PATH":"/usr/bin:/bin"]
observations.append(try observe("explicit-Process-environment", executable:"/usr/bin/python3", arguments:["-c", "import os,sys;sys.stdout.buffer.write(os.environb[b'RJT_UNICODE_TRANSPORT_PROBE'])"], environment:minimalEnvironment))
observations.append(try observe("explicit-Process-environment-via-sh", executable:"/bin/sh", arguments:["-c","printf %s \"$RJT_UNICODE_TRANSPORT_PROBE\""], environment:minimalEnvironment))
observations.append(try observe("Process-arguments", executable:"/usr/bin/printf", arguments:["%s",value], environment:["PATH":"/usr/bin:/bin"]))
observations.append(try observe("stdin-Data-utf8", executable:"/bin/cat", arguments:[], environment:["PATH":"/usr/bin:/bin"], input:Data(value.utf8)))
let output = try JSONSerialization.data(withJSONObject:observations,options:[.prettyPrinted,.sortedKeys])
try output.write(to:URL(fileURLWithPath:"/tmp/rjt-process-unicode-observation.json"))
for observation in observations { print(observation["id"]!, "UTF8Equal",observation["UTF8Equal"]!,"UTF16Equal",observation["UTF16Equal"]!,"SwiftEqual",observation["SwiftEqual"]!) }
