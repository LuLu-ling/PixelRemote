import 'dart:async';

/// GoF Command: a request encapsulated as an object and executed against a
/// receiver [R]. Senders build commands; they never touch the receiver.
abstract interface class Command<R> {
  FutureOr<void> execute(R receiver);
}

/// GoF Invoker: the single choke point every command flows through, keeping
/// senders decoupled from the receiver and centralising the error policy.
final class CommandInvoker<R> {
  CommandInvoker(this._receiver, {this.onError});

  final R _receiver;
  final void Function(Object error, StackTrace stack)? onError;

  Future<void> dispatch(Command<R> command) async {
    try {
      await command.execute(_receiver);
    } catch (error, stack) {
      onError?.call(error, stack);
    }
  }
}
