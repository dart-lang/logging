## 0.11.0

* Revert change in `0.10.0`. `stackTrace` must be an instance of `StackTrace`.
  Use the `Trace` class from the [stack_trace package][] to convert strings.

[stack_trace package]: https://pub.dartlang.org/packages/stack_trace

## 0.10.0

* Change type of `stackTrace` from `StackTrace` to `Object`.

## 0.9.3

* Added optional `LogRecord.zone` field.

* Record current zone (or user specified zone) when creating new `LogRecord`s.

