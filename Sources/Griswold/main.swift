import Foundation
import GriswoldKit

// Developer tools: `Griswold --snapshot out.png` renders the simulation to a
// file instead of launching the app. Everything else starts the menu bar app.
let arguments = CommandLine.arguments
if SnapshotCommand.handles(arguments) {
    exit(SnapshotCommand.run(arguments))
}
GriswoldApp.run()
