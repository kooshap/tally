# Tally

A net worth tracker for iPhone that works entirely offline.

Every mainstream net worth app asks you to hand your bank credentials to an
aggregator. Tally doesn't. You type in what you own and what you owe, and the
numbers stay in a local SwiftData store on your device. There is no account, no
sign-in, no sync, and no networking code anywhere in the app.

## Status

Early scaffold. The model layer and core screens exist; it has not yet been
built or run on a device.

## What's here

```
project.yml            XcodeGen spec — the Xcode project is generated, not committed
Tally/
  TallyApp.swift       App entry point, local-only model container
  Models/              Account, ValueSnapshot, AccountKind, NetWorthSummary
  Views/               Net worth header, account list, add/edit, value history
  Support/             Currency formatting
TallyTests/            Unit tests for the arithmetic and model behaviour
```

## Data model

An **Account** is one thing you own or owe. Its worth is the most recent
**ValueSnapshot**; older snapshots are kept, so every balance has a history you
can look back through. **AccountKind** alone decides which side of the ledger an
account falls on, so a mortgage of 400,000 is stored as a positive 400,000 and
subtracted at the point of totalling — balances are never stored negative.

All money is `Decimal`, not `Double`, so repeated addition doesn't drift.

## Building

Requires a Mac with Xcode 15 or later (SwiftData needs iOS 17+).

```sh
brew install xcodegen
xcodegen generate
open Tally.xcodeproj
```

`Tally.xcodeproj` is generated and gitignored — change targets and build
settings in `project.yml`, then re-run `xcodegen generate`.

Set your own `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` in
`project.yml` before running on a physical device.

## Tests

In Xcode, ⌘U. From the command line:

```sh
xcodebuild test -scheme Tally -destination 'platform=iOS Simulator,name=iPhone 15'
```

## One currency

Tally has no exchange rates, because fetching them would mean going online.
Accounts are therefore assumed to share a single currency — mixing them would
silently produce a wrong total. Multi-currency support would need rates entered
by hand, which is a deliberate open question rather than an oversight.

## Roadmap

- [ ] Net worth over time, charted from the snapshot history
- [ ] Encrypted local backup / restore via a file you control
- [ ] Recurring reminders to update balances
- [ ] Per-account currency with hand-entered rates
- [ ] App icon and launch screen

## License

MIT — see [LICENSE](LICENSE).
