import Foundation
let editedText = "$5.00\\Temp\r\n e\u{301} 🧪"
let original = "e\u{301} Hills, Inc"
let newer = "é Hills, Inc"
let hypotheticalEscapedOriginal = "e\\u{301} Hills, Inc"
let observation: [String: Any] = [
    "sourceSHA256": "999bb7ca2aa276a257710212d09288fd15ddac1ea3a3a484ee1a53f8ec99a534",
    "actualOriginalCanonicalEqual": original == newer,
    "actualOriginalUTF16Different": !original.utf16.elementsEqual(newer.utf16),
    "actualOriginalUTF16": Array(original.utf16),
    "actualNewerUTF16": Array(newer.utf16),
    "actualEditedContainsCRLF": editedText.contains("\r\n"),
    "actualEditedHasDecomposedAcute": Array(editedText.unicodeScalars).contains { $0.value == 0x301 },
    "actualEditedHasOneLiteralBackslashBeforeTemp": editedText.contains("\\Temp") && !editedText.contains("\\\\Temp"),
    "hypotheticalDoubleEscapedCanonicalEqual": hypotheticalEscapedOriginal == newer
]
let data = try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
