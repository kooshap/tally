# Tally

Private, local-first iOS net worth tracker. SwiftUI, SwiftData, Swift Charts,
no third-party packages. `SPEC.md` is the source of truth for behaviour: read
it before changing a feature, and update it in the same commit when behaviour
changes.

## Setup

- `Tally.xcodeproj` is generated and gitignored. Edit `project.yml`, and run
  `BuildTools/tool xcodegen generate` after adding, removing or renaming files.
- Run swift-format, SwiftLint and XcodeGen only through `BuildTools/tool`,
  which pins the versions CI uses.

## Before every commit

Run all of these and fix every failure. They mirror CI, and the pre-commit
hook covers only the first two, on staged files.

```sh
BuildTools/tool swift-format lint --strict --recursive --parallel Tally TallyTests TallyUITests
BuildTools/tool swiftlint lint --strict --quiet
xcodebuild clean build-for-testing -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath build/analyze CODE_SIGNING_ALLOWED=NO > build/xcodebuild.log 2>&1 || tail -50 build/xcodebuild.log
BuildTools/tool swiftlint analyze --strict --quiet --compiler-log-path build/xcodebuild.log
xcodebuild test -scheme Tally -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TallyTests -quiet CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

- `swiftlint analyze` catches unused imports; plain lint doesn't.
- For a UI change, also run `-only-testing:TallyUITests`, and look at the
  change in the simulator, in light and dark mode.
- If tests fail with "failed preflight checks" or hang, the simulator isn't
  ready: `xcrun simctl boot <udid>`, then `xcrun simctl bootstatus <udid> -b`,
  and run again with `-destination id=<udid>`.

## Code rules

- Money is `Decimal` everywhere. Convert to `Double` only through `.plotted`
  (`Tally/Views/ChartPlotting.swift`), and only for drawing charts.
- Balance and rate dates are `CalendarDay`, never `Date`.
- The only network call is the ECB rates download. Add no analytics, no
  crash reporting and no other hosts.
- Put logic in `Tally/Domain` or `Tally/Forms`, with unit tests. Keep views thin.

## Strings

`Tally/Resources/Localizable.xcstrings` is maintained by hand.

- Every new user-facing string needs an entry with a German translation.
  `GermanLocalizationUITests` fails if German screens fall back to English.
- Write integer interpolations as `\(n, specifier: "%lld")`.
- Builds and exports can rewrite the catalog. After building, check
  `git diff`, and `git checkout` the catalog if you didn't mean to change it.

## Git

- Commit directly on `main`, only when asked. Never push unless asked.
- No `Co-Authored-By` trailers.
- The subject says what changed for the user, in sentence case. The body says
  why, wrapped at about 72 columns.
