import Foundation

public enum VoiceInkPreferenceList {
    public static func removing<Element>(at offsets: IndexSet, from elements: [Element]) -> [Element] {
        var updatedElements = elements

        for index in offsets.sorted(by: >) where updatedElements.indices.contains(index) {
            updatedElements.remove(at: index)
        }

        return updatedElements
    }
}
