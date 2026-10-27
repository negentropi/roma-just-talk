import AppKit
import Foundation
final class Provider:NSObject,NSPasteboardItemDataProvider {
 func pasteboard(_ board:NSPasteboard?,item:NSPasteboardItem,provideDataForType type:NSPasteboard.PasteboardType) {}
}
let board=NSPasteboard.withUniqueName()
defer {board.releaseGlobally()}
let provider=Provider(),item=NSPasteboardItem(),type=NSPasteboard.PasteboardType("com.negentropi.RomaJustTalk.tests.unreadable")
let declared=item.setDataProvider(provider,forTypes:[type])
let written=board.writeObjects([item]);let before=board.changeCount
let actual=board.pasteboardItems ?? [];let unreadable=actual.first?.data(forType:type)==nil
let value:[String:Any] = ["classification":"actual-owned-unreadable-format-fixture","declared":declared,"written":written,"itemCount":actual.count,"types":actual.first?.types.map(\.rawValue) ?? [],"dataUnreadable":unreadable,"generationStable":board.changeCount==before,"scope":"Unique ephemeral pasteboard only; no general clipboard, app, CursorPaster or editor"]
print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
precondition(declared && written && actual.count==1 && unreadable && board.changeCount==before)
withExtendedLifetime(provider) {}
