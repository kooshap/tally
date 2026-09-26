import SwiftUI

extension View {
    /// Says a change wasn't saved. Each user action saves at once rather than
    /// waiting for autosave, which runs when SwiftData chooses: a crash before
    /// then would lose what was just entered, and a failure in it goes
    /// unreported.
    ///
    /// A failed change isn't rolled back, since SwiftData's rollback doesn't
    /// reliably reset the models on screen. It stays pending in the context,
    /// and the next save, whichever screen makes it, writes it too.
    func saveFailedAlert(isPresented: Binding<Bool>) -> some View {
        alert(
            "Couldn't save",
            isPresented: isPresented,
            actions: {},
            message: {
                Text(
                    "Your change hasn't been stored yet. Tally will try again the next time it saves. If your iPhone is low on storage, free some up."
                )
            }
        )
    }
}
