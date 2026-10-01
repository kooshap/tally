import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings' export and import of the backup file (§6).
struct BackupSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppLock.self) private var lock
    @Environment(\.modelContext) private var modelContext

    @State private var document: BackupDocument?
    @State private var isExporting = false
    @State private var exportFailed = false
    @State private var isImporting = false
    @State private var pendingImport: BackupImport?
    @State private var isUpToDate = false
    @State private var problems: [BackupProblem] = []
    @State private var saveFailed = false

    /// More would make the alert taller than the screen.
    private static let shownProblems = 5

    var body: some View {
        Section {
            Button("Export backup") {
                Task { await export() }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: .commaSeparatedText,
                defaultFilename: Backup.fileName()
            ) { result in
                if case .failure = result { exportFailed = true }
                document = nil
            }

            Button("Import backup") {
                isImporting = true
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText]) { result in
                if case .success(let url) = result {
                    prepareImport(from: url)
                }
            }
        } header: {
            Text("Backup file")
        } footer: {
            Text(
                "A CSV file of your accounts and balances, to keep in Files or move to a new iPhone. It isn't encrypted, so keep it somewhere private."
            )
        }
        .alert(
            "Import backup?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { plan in
            Button("Import") { runImport(plan) }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(plan.summary)
        }
        .alert("Already up to date", isPresented: $isUpToDate) {
        } message: {
            Text("Every account and balance in this file is already on this iPhone.")
        }
        .alert(
            "Couldn't import",
            isPresented: Binding(get: { !problems.isEmpty }, set: { if !$0 { problems = [] } })
        ) {
        } message: {
            Text(problemsText)
        }
        .alert("Couldn't export", isPresented: $exportFailed) {
        } message: {
            Text("The backup file wasn't saved.")
        }
        .saveFailedAlert(isPresented: $saveFailed)
    }

    private var problemsText: String {
        var lines = problems.prefix(Self.shownProblems).map(\.message)
        let more = problems.count - Self.shownProblems
        if more > 0 {
            lines.append(String(localized: "And \(more, specifier: "%lld") more."))
        }
        lines.append(String(localized: "Nothing was changed."))
        return lines.joined(separator: "\n\n")
    }

    private func export() async {
        if settings.faceIDEnabled {
            guard await lock.confirmOwner(reason: String(localized: "Confirm it's you to export your balances."))
            else { return }
        }
        do {
            let accounts = try modelContext.fetch(FetchDescriptor<Account>())
            document = BackupDocument(text: Backup(exporting: accounts).csv)
            isExporting = true
        } catch {
            exportFailed = true
        }
    }

    private func prepareImport(from url: URL) {
        do {
            let backup = try Backup.read(from: url, allowedDays: BalanceStore.allowedDays())
            let plan = try BackupImport(backup, into: try fetchAccounts())
            if plan.changesNothing {
                isUpToDate = true
            } else {
                pendingImport = plan
            }
        } catch {
            problems = error.problems
        }
    }

    private func fetchAccounts() throws(BackupError) -> [Account] {
        do {
            return try modelContext.fetch(FetchDescriptor<Account>())
        } catch {
            throw BackupError([.unreadableFile])
        }
    }

    private func runImport(_ plan: BackupImport) {
        plan.apply(in: modelContext)
        do {
            try modelContext.save()
        } catch {
            saveFailed = true
        }
    }
}

/// The exported CSV, handed to the Save to Files sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
