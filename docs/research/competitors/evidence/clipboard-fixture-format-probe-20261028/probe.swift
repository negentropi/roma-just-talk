import AppKit
import Foundation
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
let first = NSPasteboardItem(), second = NSPasteboardItem()
let binary = NSPasteboard.PasteboardType("com.negentropi.RomaJustTalk.tests.clipboard-lease.binary")
let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jQ3sAAAAASUVORK5CYII=")!
let source = "Original cafe\u{301} 🧬\r\nC "
let other = "Second item 🧿\r\n"
let raw = Data("{\\rtf1\\ansi Second item}".utf8)
precondition(first.setString(source,forType:.string) && first.setData(png,forType:.png) && first.setData(Data([0,255,1,128,0,13,10]),forType:binary))
precondition(second.setString(other,forType:.string) && second.setData(raw,forType:.rtf))
board.clearContents();precondition(board.writeObjects([first,second]))
let before=board.changeCount
let value=(board.pasteboardItems ?? []).enumerated().map { index,item in
 ["index":index,"types":item.types.map { ["type":$0.rawValue,"dataBase64":item.data(forType:$0)?.base64EncodedString() ?? "<unreadable>"] }] as [String:Any]
}
precondition(before==board.changeCount)
let written=board.pasteboardItems!
let firstRead=written[0], secondRead=written[1]
let declared = [
 firstRead.data(forType:.string)==Data(source.utf8),firstRead.data(forType:.png)==png,
 firstRead.data(forType:binary)==Data([0,255,1,128,0,13,10]),secondRead.data(forType:.string)==Data(other.utf8),secondRead.data(forType:.rtf)==raw
]
let captured=written.map { item in item.types.sorted { $0.rawValue < $1.rawValue }.map { ($0,item.data(forType:$0)!) } }
board.clearContents();precondition(board.setString("temporary replacement",forType:.string))
let reconstructed=captured.map { formats in
 let item=NSPasteboardItem();for (type,data) in formats {precondition(item.setData(data,forType:type))};return item
}
board.clearContents();precondition(board.writeObjects(reconstructed))
let restored=(board.pasteboardItems ?? []).map { item in item.types.sorted { $0.rawValue < $1.rawValue }.map { ($0,item.data(forType:$0)!) } }
let exactRestore=captured.count==restored.count && zip(captured,restored).allSatisfy { a,b in a.count==b.count && zip(a,b).allSatisfy { l,r in l.0==r.0 && l.1==r.1 } }
precondition(exactRestore)
let payload:[String:Any] = ["allActualFormatsRestoredExactly":exactRestore,"classification":"actual-owned-unique-pasteboard-fixture-probe","items":value,"stableChangeCount":before,"allFiveDeclaredReadbacks":declared,"scope":"Ephemeral unique pasteboard only; no general clipboard, app, editor, signing or CI-runtime claim"]
let result=try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys,.prettyPrinted])
print(String(decoding:result,as:UTF8.self))
