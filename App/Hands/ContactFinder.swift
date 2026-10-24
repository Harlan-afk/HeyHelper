import Contacts
import Foundation

/// Finds the phone number for "Mom", "Jake", etc. in your contacts, allowing for mishearing.
final class ContactFinder {
    func phoneNumber(for who: String) async -> String? {
        let dialable = who.filter { $0.isNumber || $0 == "+" }
        if dialable.filter(\.isNumber).count >= 3 { return dialable }

        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else { return nil }
        return await Task.detached(priority: .userInitiated) {
            Self.search(store: store, for: who)
        }.value
    }

    private static func search(store: CNContactStore, for who: String) -> String? {
        let target = FuzzyMatch.normalize(who)
        guard !target.isEmpty else { return nil }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var best: (score: Double, number: String)?
        try? store.enumerateContacts(with: request) { contact, _ in
            guard let number = contact.phoneNumbers.first?.value.stringValue else { return }
            let names = [contact.nickname, contact.givenName, contact.familyName, contact.givenName + contact.familyName]
                .map(FuzzyMatch.normalize)
                .filter { !$0.isEmpty }
            let score = names.map { FuzzyMatch.similarity($0, target) }.max() ?? 0
            if score >= 0.7, score > (best?.score ?? 0) { best = (score, number) }
        }
        return best?.number.filter { $0.isNumber || $0 == "+" }
    }
}
