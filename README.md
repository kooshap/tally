# Tally

A private, local-first net worth tracker for iPhone. You update your balances by
hand, roughly once a month; Tally converts every account into one portfolio
currency and charts your net worth over time.

Built to [SPEC.md](SPEC.md).

## Principles

- **Your data never leaves the device.** No account, no sync, no analytics, no
  crash reporting, no third-party packages.
- **One network call, and it isn't about you.** Tally downloads the European
  Central Bank's public exchange-rate file over an ephemeral `URLSession`
  carrying no cookies, identifiers, or app data. A unit test asserts that the
  ECB is the only host ever contacted.
- **No CloudKit.** The SwiftData store sits in Application Support and rides
  along in the standard encrypted iPhone backup. That is the backup strategy.
- **Fully usable offline**, on the last rates it cached, which it dates for you.
- App Store privacy label: **Data Not Collected**, with a `PrivacyInfo.xcprivacy`
  declaring the one required-reason API in use (`UserDefaults`, CA92.1).

## Status

Scaffolded on Linux, then first built and tested on a Mac on 2026-09-23
(Xcode 27, iOS 26.5 simulator): the full suite passes, 103 tests including
the UI test.

The ECB endpoints were fetched live on 2026-09-22 (daily = 29 currencies,
90-day = 64 business days, full history = 7,098 days back to 1999-01-04), and
the parser tests run against byte-faithful fixtures cut from those downloads.

## Building

Requires a Mac with Xcode 16 (iOS 18 SDK).

```sh
brew install xcodegen
xcodegen generate
open Tally.xcodeproj
```

`Tally.xcodeproj` is generated and gitignored — edit `project.yml` and re-run
`xcodegen generate`. Set your own `DEVELOPMENT_TEAM` there before running on a
device.

## Layout

```
project.yml                 XcodeGen spec (iOS 18, iPhone, portrait)
SPEC.md                     The build spec this implements
Tally/
  Domain/                   Pure value types — no SwiftData, no SwiftUI
    CalendarDay             A day with no time zone (see below)
    AccountType             bank / broker / realEstate / debt, and the sign
    RateTable               Rate lookup and EUR-pivot conversion
    NetWorthCalculator      §4 in full: carry-forward, archiving, frozen rates
    CurrencyCatalog         The 29 ECB currencies, plus EUR
  Models/                   SwiftData: Account, BalanceEntry, FXRate
    BalanceStore            The one-entry-per-day and archive rules
    RateStore               Merge-by-day-and-currency
    AppSettings             Base currency, Face ID, last fetch
  Rates/                    ECBEndpoint, ECBRatesParser, RatesService, coordinator
  Views/                    Dashboard + 3 chart modes, accounts, update-all, settings
  Resources/                String Catalog (en/de), PrivacyInfo.xcprivacy
TallyTests/                 Domain, store, parser, and network-host tests
TallyUITests/               The "update all" flow
```

## Two decisions worth knowing

**Days are not `Date`s.** `CalendarDay` stores `yyyymmdd` as an integer. A
balance is a fact about a day, not a moment: storing instants would mean a
figure entered on the 31st in Zurich could read as the 30th or the 1st depending
on where it is opened, and matching an entry to that day's ECB rate would depend
on the reader's time zone. This also makes "one entry per account per day" an
exact integer comparison.

**Rates are stored against the euro and never re-priced.** The ECB publishes
units-per-euro, and that is what gets cached. Converting C→B routes through EUR
using *day D's* rates, so changing your portfolio currency re-prices the entire
history correctly from data already on the device, with no re-fetch. A past
point is never recomputed with today's rates — the line you saw last month is
the line you see now.

Only rates from 2015 on are kept (the ECB file starts in 1999, but it is one
download either way). That is 93,000 rows instead of 221,000. To match, a
balance can't be dated before 2015, so every entry has a rate to convert with.

When no rate exists on or before a day, that day is marked "rates missing",
excluded from the chart, and explained in a banner with a retry. It is never
estimated, interpolated, or filled from a later rate.

## Tests

`⌘U` in Xcode, or:

```sh
xcodebuild test -scheme Tally -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The scheme gathers code coverage for the app target; read it in Xcode's
Report navigator, or with `xcrun xccov view --report <result bundle>`.

Covering conversion and the EUR pivot, carry-forward, archive and unarchive,
missing-rate handling, base-currency change, same-day entry merging, time-zone
and DST stability, the three real ECB file shapes (including `N/A` rates and a
truncated file), and a `URLProtocol` recorder standing in for §8's network
monitor.

## Not in v1

Individual securities, reminders, CloudKit, iPad and Mac, widgets, file
export/import, amortization, ownership shares, and any currency the ECB does not
publish. See [SPEC.md §7](SPEC.md).

## License

MIT — see [LICENSE](LICENSE).
