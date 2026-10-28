func commit<Value>(_ changes: (Int) throws -> Value) rethrows -> Value {
    try changes(1)
}
struct PreparedImport {
    func rows(using context: Int, additionalExistingWords: [String], additionalExistingRecords: [String]) throws -> [Int] {
        [context]
    }
    func apply() throws -> [Int] {
        let rows = try commit { writer in
            let rows = try rows(using: writer, additionalExistingWords: [], additionalExistingRecords: [])
            return rows
        }
        return rows
    }
}
