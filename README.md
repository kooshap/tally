<img src="Branding/tally-logo.svg" alt="Tally logo" width="96">

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
- **The store is never thrown away.** Before an update migrates it, Tally
  copies the store and its `-wal`/`-shm` files to `Store Backups/` in
  Application Support, keeping the newest three. If the store won't open,
  the app says the data is still there and offers "Try again" instead of
  crashing; nothing on that screen deletes, replaces, or recreates the file.
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

Requires a Mac with Xcode 16 (iOS 18 SDK) or later. The app builds in the
Swift 6 language mode.

```sh
brew bundle                        # lefthook
lefthook install                   # the pre-commit hook
BuildTools/tool xcodegen generate
open Tally.xcodeproj
```

`Tally.xcodeproj` is generated and gitignored — edit `project.yml` and re-run
`BuildTools/tool xcodegen generate`. `DEVELOPMENT_TEAM` there is the team Xcode
Cloud signs with; change it to your own to run a fork on a device.

## Layout

```
project.yml                 XcodeGen spec (iOS 18, iPhone, portrait)
SPEC.md                     The build spec this implements
BuildTools/                 Pinned XcodeGen, swift-format, and SwiftLint
Tally/
  Domain/                   Pure value types — no SwiftData, no SwiftUI
    CalendarDay             A day with no time zone (see below)
    AccountType             bank / broker / realEstate / debt, and the sign
    RateTable               Rate lookup and EUR-pivot conversion
    NetWorthCalculator      §4 in full: carry-forward, archiving, frozen rates
    CurrencyCatalog         The 29 ECB currencies, plus EUR
  Models/                   SwiftData: Account, BalanceEntry, FXRate
    TallySchema             Versioned schema and migration plan — read it
                            before changing a model
    StoreBackups            The copy taken before a migration, and pruning
    StoreLoader             Opening at launch, and the failure it shows
    BalanceStore            The one-entry-per-day and archive rules
    RateStore               Merge-by-day-and-currency
    AppSettings             Base currency, Face ID, last fetch
  Forms/                    What the account and balance editors save, and when
  Rates/                    ECBEndpoint, ECBRatesParser, RatesService, coordinator
  Views/                    Dashboard + 3 chart modes, accounts, update-all, settings,
                            and the screen shown when the store won't open
  Resources/                String Catalog (en/de), PrivacyInfo.xcprivacy
TallyTests/                 Domain, store, form, parser, migration, and
                            network-host tests
TallyUITests/               The "update all" flow, and the recovery screen
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

`SchemaMigrationTests` opens `Fixtures/tally-v1.store`, a store written by the
app before its models were versioned, and checks that every account, balance,
and rate survives. It also fails if `TallySchemaV1` is edited in place: a model
change belongs in a new schema version with a migration stage, and the fixture
must still open under it.

`StoreBackupTests` checks a copy of the store and its sidecars is taken
only when opening it would migrate it, that the same store is never copied
twice, and that only the newest three are kept. `StoreLoaderTests` opens a few
random bytes as a store: the app reaches the recovery state, "Try again" keeps
failing safely, and the file is byte-for-byte what it was. A UI test launches
the real app against such a store.

The rules the editors apply — validation, which amounts may be negative, which
entry a swipe deletes, when the app re-locks — live in `Forms/`, `BalanceStore`,
and `AppLock`, where they are unit tested; what's left in the views is layout.

## Code style

`swift-format` owns layout (`.swift-format`: 4 spaces, 120 columns) and
SwiftLint checks the rest (`.swiftlint.yml`, which turns off the rules that
would fight the formatter). The pre-commit hook formats and lints the Swift
files being committed. To run them over everything:

```sh
BuildTools/tool swift-format format --in-place --recursive Tally TallyTests TallyUITests
BuildTools/tool swiftlint lint --strict
```

`BuildTools/tool` runs XcodeGen, swift-format, and SwiftLint at the versions
pinned in `BuildTools/`, installing each on first use; swift-format is built
from source, which takes a couple of minutes the first time. The hook, CI, and
Xcode Cloud all go through it, so a new release upstream can't change what
counts as clean. To upgrade a tool, see the top of `BuildTools/tool`.

On every push, CI runs both alongside the full test suite, which it builds
with warnings treated as errors.

## Not in v1

Individual securities, reminders, CloudKit, iPad and Mac, widgets, file
export/import, amortization, ownership shares, and any currency the ECB does not
publish. See [SPEC.md §7](SPEC.md).

## License

MIT — see [LICENSE](LICENSE).
