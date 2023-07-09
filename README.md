[![Build Status](https://github.com/dart-lang/logging/workflows/Dart%20CI/badge.svg)](https://github.com/dart-lang/logging/actions?query=workflow%3A"Dart+CI"+branch%3Amaster)
[![Pub](https://img.shields.io/pub/v/logging.svg)](https://pub.dev/packages/logging)
[![package publisher](https://img.shields.io/pub/publisher/logging.svg)](https://pub.dev/packages/logging/publisher)

## Initializing

By default, the logging package does not do anything useful with the log
messages. You must configure the logging level and add a handler for the log
messages.

Here is a simple logging configuration that logs all messages via `print`.

```dart
Logger.root.level = Level.ALL; // defaults to Level.INFO
Logger.root.onRecord.listen((record) {
  print('${record.level.name}: ${record.time}: ${record.message}');
});
```

First, set the root `Level`. All messages at or above the current level are sent to the
`onRecord` stream. Available levels are:

+ `Level.OFF`
+ `Level.SHOUT`
+ `Level.SEVERE`
+ `Level.WARNING`
+ `Level.INFO`
+ `Level.CONFIG`
+ `Level.FINE`
+ `Level.FINER`
+ `Level.FINEST`

Then, listen on the `onRecord` stream for `LogRecord` events. The `LogRecord`
class has various properties for the message, error, logger name, and more.

To listen for changed level notitfications use:

```dart
Logger.root.onLevelChanged.listen((level) {
  print('The new log level is $level');
});
```

## Logging messages

Create a `Logger` with a unique name to easily identify the source of the log
messages.

```dart
final log = Logger('MyClassName');
```

Here is an example of logging a debug message and an error:

```dart
var future = doSomethingAsync().then((result) {
  log.fine('Got the result: $result');
  processResult(result);
}).catchError((e, stackTrace) => log.severe('Oh noes!', e, stackTrace));
```

When logging more complex messages, you can pass a closure instead that will be
evaluated only if the message is actually logged:

```dart
log.fine(() => [1, 2, 3, 4, 5].map((e) => e * 4).join("-"));
```

Available logging methods are:

+ `log.shout(logged_content);`
+ `log.severe(logged_content);`
+ `log.warning(logged_content);`
+ `log.info(logged_content);`
+ `log.config(logged_content);`
+ `log.fine(logged_content);`
+ `log.finer(logged_content);`
+ `log.finest(logged_content);`

## Configuration

Loggers can be individually configured and listened to. When an individual logger has no
specific configuration, it uses the configuration and any listeners found at `Logger.root`.

To begin, set the global boolean `hierarchicalLoggingEnabled` to `true`.

Then, create unique loggers and configure their `level` attributes and assign any listeners to
their `onRecord` streams.


```dart
hierarchicalLoggingEnabled = true;

Logger.root.level = Level.FINE;

final log1 = Logger('WARNING+');
log1.level = Level.WARNING;
Logger.root.onRecord.listen((record) {
  print('[WARNING+] ${record.message}');
});

final log2 = Logger('FINE+'); // Inherited from `Logger.root`
log2.onRecord.listen((record) {
  print('[FINE+]    ${record.message}');
});

log1.info('Will not print because too low level');
log2.info(
  'WILL print TWICE ([FINE+] and [WARNING+]) '
  'because `log2` uses individual and root listeners',
);

log1.warning('WILL print ONCE because `log1` only uses root listener');
log2.warning(
  'WILL print TWICE because `log2` '
  'uses individual and root listeners',
);
```

Results in:

```
[FINE+]    WILL print TWICE ([FINE+] and [WARNING+]) because `log2` uses individual and root listeners
[WARNING+] WILL print TWICE ([FINE+] and [WARNING+]) because `log2` uses individual and root listeners
[WARNING+] WILL print ONCE because `log1` only uses root listener
[FINE+]    WILL print TWICE because `log2` uses individual and root listeners
[WARNING+] WILL print TWICE because `log2` uses individual and root listeners
```

## Publishing automation

For information about our publishing automation and release process, see
https://github.com/dart-lang/ecosystem/wiki/Publishing-automation.
