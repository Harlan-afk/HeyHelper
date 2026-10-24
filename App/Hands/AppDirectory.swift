import Foundation

/// Apps Helper knows how to open. iPhone apps can only be opened through their link
/// ("URL scheme"), so unknown apps can be added in Settings with a link or a Shortcut name.
enum AppDirectory {
    struct Entry {
        let name: String
        let aliases: [String]
        let link: String
    }

    static let builtIn: [Entry] = [
        // Apple apps
        Entry(name: "App Store", aliases: ["appstore", "store"], link: "itms-apps://"),
        Entry(name: "Books", aliases: ["apple books", "ibooks"], link: "ibooks://"),
        Entry(name: "Calendar", aliases: ["calender", "my calendar"], link: "calshow://"),
        Entry(name: "Clock", aliases: ["alarm", "alarms", "stopwatch"], link: "clock-alarm://"),
        Entry(name: "FaceTime", aliases: ["face time"], link: "facetime://"),
        Entry(name: "Files", aliases: ["my files"], link: "shareddocuments://"),
        Entry(name: "Find My", aliases: ["find my iphone", "findmy"], link: "findmy://"),
        Entry(name: "Health", aliases: ["apple health"], link: "x-apple-health://"),
        Entry(name: "Mail", aliases: ["email", "apple mail"], link: "message://"),
        Entry(name: "Maps", aliases: ["apple maps", "map"], link: "maps://"),
        Entry(name: "Messages", aliases: ["imessage", "texts", "text messages"], link: "sms:"),
        Entry(name: "Music", aliases: ["apple music"], link: "music://"),
        Entry(name: "Notes", aliases: ["my notes"], link: "mobilenotes://"),
        Entry(name: "Photos", aliases: ["gallery", "pictures", "camera roll"], link: "photos-redirect://"),
        Entry(name: "Podcasts", aliases: ["apple podcasts"], link: "podcasts://"),
        Entry(name: "Reminders", aliases: ["reminder"], link: "x-apple-reminderkit://"),
        Entry(name: "Safari", aliases: ["browser", "internet"], link: "x-web-search://"),
        Entry(name: "Settings", aliases: ["setting", "preferences"], link: "app-settings:"),
        Entry(name: "Shortcuts", aliases: ["shortcut"], link: "shortcuts://"),
        Entry(name: "Wallet", aliases: ["apple pay", "apple wallet"], link: "shoebox://"),
        Entry(name: "Weather", aliases: ["forecast"], link: "weather://"),
        // Popular apps
        Entry(name: "Amazon", aliases: ["amazon shopping"], link: "com.amazon.mobile.shopping://"),
        Entry(name: "Cash App", aliases: ["cashapp", "cash"], link: "squarecash://"),
        Entry(name: "ChatGPT", aliases: ["chat gpt"], link: "chatgpt://"),
        Entry(name: "Chrome", aliases: ["google chrome"], link: "googlechrome://"),
        Entry(name: "Discord", aliases: ["discord app"], link: "discord://"),
        Entry(name: "Disney+", aliases: ["disney plus", "disney"], link: "disneyplus://"),
        Entry(name: "DoorDash", aliases: ["door dash"], link: "doordash://"),
        Entry(name: "Duolingo", aliases: ["duo lingo"], link: "duolingo://"),
        Entry(name: "Facebook", aliases: ["fb"], link: "fb://"),
        Entry(name: "Gmail", aliases: ["google mail", "g mail"], link: "googlegmail://"),
        Entry(name: "Google", aliases: ["google search", "google app"], link: "google://"),
        Entry(name: "Google Maps", aliases: ["googlemaps"], link: "comgooglemaps://"),
        Entry(name: "Hulu", aliases: ["hulu app"], link: "hulu://"),
        Entry(name: "Instagram", aliases: ["insta", "ig"], link: "instagram://"),
        Entry(name: "Messenger", aliases: ["facebook messenger"], link: "fb-messenger://"),
        Entry(name: "Minecraft", aliases: ["mine craft"], link: "minecraft://"),
        Entry(name: "Netflix", aliases: ["net flicks"], link: "nflx://"),
        Entry(name: "Outlook", aliases: ["microsoft outlook"], link: "ms-outlook://"),
        Entry(name: "PayPal", aliases: ["pay pal"], link: "paypal://"),
        Entry(name: "Pinterest", aliases: ["pin trest"], link: "pinterest://"),
        Entry(name: "Reddit", aliases: ["red it"], link: "reddit://"),
        Entry(name: "Roblox", aliases: ["row blocks", "roblocks"], link: "roblox://"),
        Entry(name: "Shazam", aliases: ["what song is this"], link: "shazam://"),
        Entry(name: "Snapchat", aliases: ["snap"], link: "snapchat://"),
        Entry(name: "Spotify", aliases: ["spot a fly", "spotty"], link: "spotify://"),
        Entry(name: "Teams", aliases: ["microsoft teams"], link: "msteams://"),
        Entry(name: "Telegram", aliases: ["telegram app"], link: "tg://"),
        Entry(name: "TikTok", aliases: ["tick tock", "tik tok"], link: "snssdk1233://"),
        Entry(name: "Twitch", aliases: ["twitch tv"], link: "twitch://"),
        Entry(name: "Uber", aliases: ["uber app"], link: "uber://"),
        Entry(name: "Uber Eats", aliases: ["ubereats"], link: "ubereats://"),
        Entry(name: "Venmo", aliases: ["venmo app"], link: "venmo://"),
        Entry(name: "Waze", aliases: ["ways"], link: "waze://"),
        Entry(name: "WhatsApp", aliases: ["whats app"], link: "whatsapp://"),
        Entry(name: "X", aliases: ["twitter"], link: "twitter://"),
        Entry(name: "YouTube", aliases: ["you tube", "yt"], link: "youtube://"),
        Entry(name: "YouTube Music", aliases: ["yt music"], link: "youtubemusic://"),
        Entry(name: "Zoom", aliases: ["zoom meeting"], link: "zoomus://"),
    ]

    /// Finds the app the user most likely meant, even if the name came out wrong.
    static func find(_ spoken: String, custom: [CustomApp]) -> (name: String, url: URL)? {
        let filler: Set<String> = ["the", "my", "app", "application", "please", "up"]
        let words = spoken.lowercased().split(separator: " ").map(String.init).filter { !filler.contains($0) }
        let query = FuzzyMatch.normalize(words.joined())
        guard !query.isEmpty else { return nil }

        var candidates: [(name: String, keys: [String], url: URL)] = []
        for app in custom {
            if let url = app.url { candidates.append((app.name, [app.name], url)) }
        }
        for entry in builtIn {
            guard let url = URL(string: entry.link) else { continue }
            candidates.append((entry.name, [entry.name] + entry.aliases, url))
        }

        var best: (score: Double, name: String, url: URL)?
        for candidate in candidates {
            for key in candidate.keys {
                let normalized = FuzzyMatch.normalize(key)
                guard !normalized.isEmpty else { continue }
                var score = FuzzyMatch.similarity(query, normalized)
                if query == normalized { score = 1.0 }
                if score > (best?.score ?? 0) { best = (score, candidate.name, candidate.url) }
            }
        }
        guard let best, best.score >= 0.7 else { return nil }
        return (best.name, best.url)
    }
}
