# Helper: your offline voice assistant (with Pip)

Say **"Hey Helper"**, and Pip, a small floating companion, wakes up on your screen or lock screen, listens, thinks, and answers out loud. It can also open apps, call or text people, set timers and reminders, turn the flashlight on and off, and control your music.

- **No AI service.** The brain is an open-source model (Llama 3.2 1B) that runs on your iPhone.
- **Nothing is scripted.** The model writes every reply itself, and it works out what you meant even if speech recognition gets your words a bit wrong.
- **Smarter with lookups (optional):** when it isn't sure, it looks things up on free public sources (Wikipedia, DuckDuckGo, Open-Meteo weather) and saves what it learns so it can answer offline later. You can turn this off in Settings.
- **Remembers you:** say "remember my favorite food is tacos" and it keeps that. You can see and delete memories in Settings.
- **Plays the exact song you ask for** from your library or Apple Music (or searches Spotify), and plays voice games like trivia, riddles and 20 questions. It can open games like Clash Royale and coach you, but iOS doesn't let any app tap inside other games.
- Speech recognition runs on the phone too. Your voice never leaves it.

## How it works

| Part | What it does | File |
|---|---|---|
| Ears | Keeps the mic open, spots "Hey Helper" even when it's misheard, then records your question | `App/Ears/` |
| Brain | Runs Llama 3.2 1B on the phone through llama.cpp and streams the answer | `App/Brain/` |
| Voice | Reads each sentence aloud as soon as it's written | `App/Voice/` |
| Hands | Carries out commands the brain writes, like `[open: YouTube]` | `App/Hands/` |
| Pip | The companion, drawn in code, shown in the app and on the lock screen | `Shared/`, `Widget/` |

## Installing on your iPhone (free, no Mac)

### One-time setup
1. **Get the app file.** On GitHub, open this repository, go to **Actions**, then the latest green **Build iPhone app** run. Under **Artifacts**, download **HeyHelper-ipa** and unzip it to get `HeyHelper.ipa`.
2. **Install Sideloadly** from sideloadly.io on your Windows PC. If it asks for iTunes and iCloud, install the versions from Apple's website, not the Microsoft Store.
3. **Plug your iPhone into the PC** with a cable. Unlock it and tap **Trust**.
4. In Sideloadly, drag `HeyHelper.ipa` into the window, type your Apple ID email, and click **Start**. Sign in when it asks. Your Apple ID only goes to Apple.
5. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, and restart when asked.
6. Open **Settings → General → VPN & Device Management**, tap your Apple ID, then tap **Trust**.
7. Open **Helper**, tap **Allow**, then **Download** the brain. It's 808 MB, so use Wi-Fi and keep the app open. Then tap **Start Helper**.

### Every 7 days
Apple makes free installs expire after 7 days. When Helper stops opening, plug in and repeat step 4 with the same file. Your settings and the brain stay on the phone.

## Tips
- **Leave Helper running in the background** and don't swipe it away. Then it hears "Hey Helper" even on the lock screen. The orange dot means the mic is on.
- iOS doesn't let an app open other apps while the phone is locked. If you ask then, Helper sends a notification. Unlock and tap it.
- Listening all the time uses more battery. You can turn the wake phrase off in Settings and tap Pip instead.
- For a better voice, go to iPhone **Settings → Accessibility → Spoken Content → Voices → English**, download an **Enhanced** voice, and pick it in Helper's settings.
- For an app Helper can't open, create a Shortcut that opens it and add the Shortcut's name under **Settings → Teach me apps**.
- The brain is small enough to fit on a phone, so it sometimes gets facts wrong and doesn't know recent news.

## Building
Every push to `main` builds the app on a free GitHub cloud Mac (`.github/workflows/build-iphone-app.yml`). The workflow downloads llama.cpp, generates the Xcode project from `project.yml` with XcodeGen, and saves an unsigned `.ipa`. Sideloadly signs it when it installs.
