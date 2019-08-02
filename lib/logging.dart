// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'src/log_record.dart';
import 'src/logger.dart';

export 'src/level.dart';
export 'src/log_record.dart';
export 'src/logger.dart';

/// Handler callback to process log entries as they are added to a [Logger].
@Deprecated('Will be removed in 1.0.0')
typedef LoggerHandler = void Function(LogRecord record);
