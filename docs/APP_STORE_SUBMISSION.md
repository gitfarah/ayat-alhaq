# App Store submission kit — Ayat al-Haq (آيات الحق)

Everything needed to publish the iOS app, prepared ahead of the Apple
Developer account. Once the account exists, follow **Part B**.

- **Bundle ID:** `com.omar.ayatalhaq`
- **App name:** آيات الحق (Ayat al-Haq)
- **Version / build:** `1.0.10 (21)` — set in `pubspec.yaml`
- **Category:** Reference (secondary: Lifestyle)
- **Signed build + upload:** handled by `.github/workflows/ios-release.yml`

---

## Part A — Store listing content (copy-paste ready)

### App name / subtitle
- Name: **آيات الحق** (or "Ayat al-Haq — Quran" for the English storefront)
- Subtitle (EN): *Quran, recitation & prayer times*
- Subtitle (AR): *القرآن الكريم، التلاوة ومواقيت الصلاة*
- Subtitle (DE): *Koran, Rezitation & Gebetszeiten*

### Promotional Text (170 chars max — shown above the Description; the
only listing field you can edit anytime WITHOUT a new App Review)
- EN: *Read, listen, and reflect on the Holy Quran — fully offline, in Arabic, English or German. No ads, no account, no tracking.*
- AR: *اقرأ واستمع وتدبّر القرآن الكريم — بالكامل دون اتصال، بالعربية والإنجليزية والألمانية. بدون إعلانات، بدون حساب، بدون تتبع.*
- DE: *Lies, höre und reflektiere über den Heiligen Koran — komplett offline, auf Arabisch, Englisch oder Deutsch. Keine Werbung, kein Konto, kein Tracking.*

### Keywords (100 chars, EN example)
`quran,koran,mushaf,tafsir,recitation,prayer times,adhan,islam,muslim,offline,arabic,khatma`

### Description — English
> Ayat al-Haq is a clean, ad-free Quran companion for reading, listening, and
> daily worship.
>
> • Read the full Quran offline — all 114 surahs bundled in the app.
> • Two reading modes: the printed Mushaf (page images) and a responsive
>   verse-by-verse reader with adjustable font size.
> • Listen to verse-by-verse recitation with several reciters; playback
>   continues in the background and the screen follows along.
> • Tafsir (commentary), bookmarks, and colour highlights.
> • Prayer times for your city or your GPS location, with the next prayer
>   highlighted.
> • Khatma tracker to follow your reading of the whole Quran.
> • Full app in Arabic, English and German, with light and dark themes.
>
> No account, no ads, no tracking.

### Description — العربية
> آيات الحق تطبيق للقرآن الكريم نظيف وخالٍ من الإعلانات، للقراءة والاستماع
> والعبادة اليومية.
>
> • اقرأ القرآن كاملاً دون اتصال — جميع السور الـ١١٤ داخل التطبيق.
> • وضعان للقراءة: المصحف بالصفحات، وقراءة متجاوبة آية بآية مع حجم خط قابل
>   للتعديل.
> • استمع للتلاوة آية بآية بعدة قرّاء، مع استمرار التشغيل في الخلفية ومتابعة
>   الشاشة للآية الحالية.
> • التفسير، والفواصل (العلامات المرجعية)، وتمييز الآيات بالألوان.
> • مواقيت الصلاة حسب مدينتك أو موقعك، مع إبراز الصلاة القادمة.
> • متابعة الختمة.
> • التطبيق كامل بالعربية والإنجليزية والألمانية، بوضعين نهاري وليلي.
>
> بدون حساب، بدون إعلانات، بدون تتبع.

### Description — Deutsch
> Ayat al-Haq ist ein schlichter, werbefreier Koran-Begleiter zum Lesen,
> Hören und für die tägliche Andacht.
>
> • Lies den kompletten Koran offline — alle 114 Suren in der App.
> • Zwei Lesemodi: der gedruckte Mushaf (Seitenbilder) und ein responsiver
>   Vers-für-Vers-Leser mit einstellbarer Schriftgröße.
> • Vers-für-Vers-Rezitation mehrerer Rezitatoren; Wiedergabe läuft im
>   Hintergrund weiter, der Bildschirm folgt mit.
> • Tafsir, Lesezeichen und farbige Markierungen.
> • Gebetszeiten für deine Stadt oder deinen Standort.
> • Khatma-Fortschritt.
> • Komplett auf Arabisch, Englisch und Deutsch, hell und dunkel.
>
> Kein Konto, keine Werbung, kein Tracking.

### Support URL / Privacy Policy URL
Host `docs/privacy-policy.html` (see Part C) and use that URL for both the
**Privacy Policy URL** and, if you have nothing else, the **Support URL**.

---

## App Privacy questionnaire (App Store Connect → App Privacy)

Answer the "Data Collection" section as follows:

- **Do you collect data from this app?** → **Location** is *used* but **not
  collected** in Apple's sense (it is not sent to us or linked to a user).
  If the form insists, declare **Coarse/Precise Location** with:
  - Used for: **App Functionality** (prayer times)
  - **Not** linked to the user's identity
  - **Not** used for tracking
- Everything else (contact info, identifiers, usage data, diagnostics): **No**.
- **Third-party SDKs collecting data:** None.

**Age rating:** 4+ (no objectionable content). Under "Made for Kids": No.

**Export compliance:** Uses standard encryption only (HTTPS) → exempt. The
app already declares `ITSAppUsesNonExemptEncryption = false` in Info.plist,
so you won't be asked at upload.

---

## Part B — What to do once the Apple Developer account is active

### 1. Create the App ID and App Store record
1. developer.apple.com → Certificates, IDs & Profiles → **Identifiers** →
   register an App ID for `com.omar.ayatalhaq` (enable **Background Modes**;
   no other special capabilities are needed).
2. appstoreconnect.apple.com → **Apps → +** → create the app, pick the
   bundle ID above, set the name **آيات الحق**.

### 2. Create the signing assets (these become the GitHub secrets)
1. **Distribution certificate** → Certificates → + → *Apple Distribution*.
   Download it, open it in Keychain Access, and **export as `.p12`** (set a
   password → that's `IOS_DIST_CERT_PASSWORD`). *(This step needs a Mac, or a
   friend with one, just once. If you have no Mac at all, tell me — we can
   generate the certificate signing request and use App Store Connect's
   web tools / a cloud Mac instead.)*
2. **Provisioning profile** → Profiles → + → *App Store* → select the App ID
   and the distribution certificate. Download the `.mobileprovision`. Note
   its exact **name** (that's `IOS_PROVISION_PROFILE_NAME`).
3. **App Store Connect API key** → App Store Connect → Users and Access →
   **Integrations / Keys** → + (App Manager role). Download the `AuthKey_XXX.p8`
   **once**. Note the **Key ID** and **Issuer ID**.
4. **Team ID** → developer.apple.com → Membership → 10-character Team ID.

### 3. Add the GitHub secrets
Repo → Settings → Secrets and variables → Actions → New repository secret,
for each name below. To base64-encode a file on Windows PowerShell:
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\file")) | Set-Clipboard
```
| Secret | From |
|---|---|
| `APPLE_TEAM_ID` | Membership page |
| `IOS_PROVISION_PROFILE_NAME` | the profile's name |
| `IOS_DIST_CERT_P12_BASE64` | base64 of the `.p12` |
| `IOS_DIST_CERT_PASSWORD` | password you set on the `.p12` |
| `IOS_PROVISION_PROFILE_BASE64` | base64 of the `.mobileprovision` |
| `IOS_KEYCHAIN_PASSWORD` | any random string |
| `ASC_API_KEY_ID` | the key's ID |
| `ASC_API_ISSUER_ID` | the issuer ID |
| `ASC_API_KEY_P8_BASE64` | base64 of the `.p8` |

### 4. Run the release build
GitHub → Actions → **"iOS App Store release (signed)"** → Run workflow.
It builds a signed IPA and uploads it to App Store Connect. After ~10–30 min
of Apple processing it appears under **TestFlight / Builds**.

### 5. Finish the listing and submit
In App Store Connect: attach the build, paste the description/keywords from
Part A, add **screenshots** (6.7" iPhone required — I can generate these),
set the Privacy Policy URL, complete App Privacy + age rating, then
**Submit for Review**.

---

## Part C — Hosting the privacy policy (free)
The simplest option using this repo:
1. Repo → Settings → **Pages** → Source: `main` branch, `/docs` folder → Save.
2. The policy will be at
   `https://gitfarah.github.io/ayat-alhaq/privacy-policy.html`.
3. Edit `docs/privacy-policy.html` first and replace the contact-email
   placeholder.

> Note: the repo is currently **private**; GitHub Pages on a private repo
> needs GitHub Pro, OR make the repo public, OR host the single HTML file
> anywhere else (e.g. a free Netlify/Cloudflare Pages drop). Tell me which
> you prefer and I'll tailor it.
