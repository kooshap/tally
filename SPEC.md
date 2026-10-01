# Net Worth Tracker (iOS): Build Spec

A private, local-first iOS app for tracking personal net worth. The user updates account balances manually, roughly once a month. The app converts every currency into one portfolio currency and charts net worth over time.

## 1. Non-negotiable principles

- **No user data leaves the device.** No accounts, analytics, crash-reporting SDKs, ads, or third-party dependencies.
- **The only network call is downloading public ECB exchange-rate files.** Requests carry no user identifiers, cookies, or app data. Use an ephemeral `URLSession`.
- **No CloudKit or iCloud sync.** Data lives in a local SwiftData store and is included in the standard iPhone iCloud/device backup (the default for Application Support). This is how data survives a lost phone.
- **App Store privacy label:** "Data Not Collected". Ship a `PrivacyInfo.xcprivacy` declaring required-reason APIs actually used (e.g. UserDefaults).
- **The app works fully offline.** It uses the last cached rates and shows when they were last updated.

## 2. Platform and stack

- iOS 18+, iPhone.
- SwiftUI, SwiftData, Swift Charts, LocalAuthentication.
- Swift Concurrency; no third-party packages.
- Localization: English and German, using a String Catalog. Numbers, dates, and currencies are formatted by locale.
- Amounts show the currency's minor unit in full or not at all: €5,728.50 and €405,000, never €5,728.5. Round amounts deliberately show no cents; a currency without a minor unit in use (JPY, KRW, ISK, HUF, IDR) never shows decimals.
- All money math uses `Decimal`, never `Double`.

## 3. Domain

### Item types

| Type | Sign in net worth | Notes |
|---|---|---|
| Bank account | + | Balance may be negative (overdraft) |
| Broker account | + | One total value per account; no individual securities |
| Real estate | + | A single manually entered value |
| Debt / mortgage | − | User enters a positive outstanding balance; the app subtracts it |

- Every item has its **own currency** (ISO 4217).
- The portfolio has one **base currency**, chosen at first launch and changeable later in Settings.
- Selectable currencies are limited to those the ECB publishes, plus EUR.

### Data model (SwiftData)

**Account**
- `id`, `name`, `type` (bank / broker / realEstate / debt), `currencyCode`, `notes` (optional), `sortOrder`, `createdAt`
- `archivedOn: Date?`

**BalanceEntry**
- `id`, `account`, `date` (calendar day, no time), `amount: Decimal`, `updatedAt`
- At most **one entry per account per day**. Editing a balance again on the same day overwrites that day's entry.

**FXRate**
- `date` (ECB business day), `currencyCode`, `unitsPerEUR: Decimal`
- EUR is the pivot currency with rate 1. It is not stored.

**Settings** (a single record or UserDefaults)
- `baseCurrency`, `faceIDEnabled`, `lastRatesFetch`

## 4. Calculation rules

**Graph points.** There is one point for each calendar day on which any BalanceEntry exists, including archive days. Multiple edits on the same day produce a single point.

**Account value on day D.** This is the amount of the account's latest BalanceEntry dated on or before D (carry-forward). The value is 0 if the account has no entry yet or was archived on or before D.

**Net worth on day D.** Sum each account's value on day D, apply its sign, and convert it to the base currency using **the rates for day D**.

**Frozen rates.** A point's value uses the rates of its own date and is never re-priced with later rates. An account that wasn't updated that day is carried forward, but still converted at day D's rate.

**Conversion.** To convert from currency C to base currency B:

`value_B = amount_C / unitsPerEUR(C, D) × unitsPerEUR(B, D)`

- Use the latest ECB date on or before D, which covers weekends and holidays.
- Because rates are stored against EUR, changing the base currency recomputes all history correctly with the same historical rates.

**Missing rates.** If no rate exists on or before D (for example, offline on first launch), mark the point as "rates missing". Exclude it from the chart and show a banner with a retry button. Never guess a rate.

## 5. Exchange rates

- **Source:** ECB euro foreign exchange reference rates.
  - Daily XML: `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml`
  - Full history: `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml`
  - Claude Code should verify these endpoints before relying on them.
- **First launch:** download the full history once so that backfilled entries have historical rates. Keep only rates from 2015-01-01 on (plus the last publication before it); older rates are discarded.
- **Later launches:** if the last fetch was more than 24 hours ago, fetch the daily file (or a 90-day file to cover gaps). Merge by date and currency.
- **On failure:** do so silently, keep the cached rates, and show "Rates as of <date>" in Settings with a manual refresh button.

## 6. Features

### Accounts
- Create, edit, and reorder accounts. Choose name, type, and currency.
- **Archive:** adds a 0 balance entry on the archive date. The account disappears from the active list, but its history remains visible on the graph. Archiving can be undone.
- **Delete:** removes the account and all its entries after a confirmation that warns it rewrites history.

### Balance entry
- Enter an amount with a date picker. The date defaults to today and can be set to the past for backfilling, back to 2015-01-01 (the first rates kept). Future dates are not allowed.
- **"Update all" flow:** the main monthly action. It steps through every active account, pre-fills the last known value, and lets the user edit or skip each one. It saves all entries with one date.
- Account detail shows its entry history, with editing and deletion of individual entries.

### Dashboard and charts
- Headline: current net worth in the base currency, plus the change (and percentage, when the start is positive) since the first point in the chosen range.
- Chart modes:
  1. Total net worth (line).
  2. Breakdown by type (stacked area; debt shown as negative).
  3. Per-account drill-down (the line for one account, in its own currency with a toggle for base currency).
- Range buttons (6M, 1Y, All) limit every chart mode to recent history. A range is offered only when it holds at least two points and leaves some out.
- The line charts use a fitted scale, with dates along the bottom and amounts up the side, green when the range ended better than it began and red when worse (for a debt, falling is better).
- Tapping or dragging on the chart shows the value on a given date: the headline (or the account readout in mode 3) shows that day's figure and change, the line fades after the finger, and each point gives a haptic tick.

### Security
- Optional Face ID / passcode lock, off by default, toggled in Settings.
- Use `LAPolicy.deviceOwnerAuthentication`, so the device passcode works as a fallback.
- Add an `NSFaceIDUsageDescription`.
- When the lock is enabled, blur the app in the app switcher.

### Backup file
For keeping a copy of the data in Files and moving it to a new iPhone. Tally reads only files in its own format; files from banks or other apps are out of scope.

- **Export** writes one CSV file, `Tally-<yyyy-MM-dd>.csv`, saved with the system Save to Files sheet (not the share sheet). When the Face ID lock is on, the owner authenticates first. Settings says the file isn't encrypted.
- **Format.** RFC 4180 CSV in UTF-8, CRLF line endings, a header row, then one row per balance:

  `account_id,account_name,account_type,currency,notes,sort_order,archived_on,date,amount`

  - Account columns repeat on each of that account's rows. An account with no balances has one row with `date` and `amount` empty.
  - The format is the same in every language: `account_type` is `bank`, `broker`, `realEstate` or `debt`; dates are `yyyy-MM-dd`; amounts use a dot for decimals and no grouping (`-1234.5`); `currency` is an ISO code; `account_id` is a UUID.
  - Columns may come in any order, and unknown columns are ignored, so a later version can add some. Values are written as they are, with no spreadsheet formula escaping: they are the user's own, and escaping would change them on import.
  - Not included: exchange rates (downloaded again), settings, and the account and entry timestamps.
- **Import** picks a file with the system file picker and reads at most 5 MB. It checks the whole file before changing anything, and on any problem changes nothing and lists the first problems by line number:
  - a header that lacks a required column, a file that isn't UTF-8, or a row with more or fewer values than the header;
  - an invalid ID, empty name, unknown type, or a currency Tally doesn't offer;
  - a date that isn't valid or is outside the balance-entry range (2015-01-01 to today), for `date` and `archived_on`;
  - an amount that isn't a number, or a negative amount for a type that doesn't allow one;
  - a date without an amount or an amount without a date, or two balances for one account on one day;
  - rows of one account that disagree on its details.
- **Merge.** An account in the file matches the account on the phone with the same `account_id`; failing that, the one account with the same name (ignoring case), type and currency. A matched account keeps its details on the phone, and only its balances are merged; if its type or currency differs from the file, the import is refused. An unmatched account is added with the file's ID, details and archive date, after the existing accounts in the file's order. An imported balance is added, or replaces the balance on the same day, the same rule as entering it by hand. Nothing is deleted.
- Before importing, a confirmation says how many accounts and balances will be added and how many balances replaced. A file that would change nothing says so instead. The import saves in one go.

### Settings
- Base currency, Face ID toggle, and exchange-rate status with a refresh button.
- Export and import a backup file.
- About screen with a privacy statement.

## 7. Out of scope (v1)

- Individual stocks and ETFs, prices, or holdings.
- Reminders and notifications.
- CloudKit sync, iPad and Mac, widgets.
- Importing files from banks or other apps, and replacing all data on import.
- Interest rates, amortization, and linking mortgages to properties.
- Real-estate ownership shares.
- Crypto or any currency not published by the ECB.

## 8. Testing

- Unit tests for conversion, carry-forward, archive behaviour, missing-rate handling, base-currency change, and same-day entry merging.
- Parse tests against fixture ECB XML files.
- Backup file round trip, and import checks and merging.
- UI test for the "Update all" flow.
- Verify with a network monitor that no request goes anywhere except the ECB host.
