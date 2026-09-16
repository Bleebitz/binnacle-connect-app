/// An acknowledgment confirms the command outcome, not media availability.
/// Library entries must arrive independently from the Core media catalog.
enum CommandOutcome { acknowledged, rejected, timedOut, disconnected }

class CommandResult {
  final CommandOutcome outcome;
  final String? reason;
  const CommandResult(this.outcome, [this.reason]);
}
