import Foundation

extension String {
    var nfsNormalizedSearchText: String {
        // Search normalization must not change with the user's current
        // locale. In particular, Turkish casing rules can otherwise make a
        // database built under one locale disagree with a query under
        // another.
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
