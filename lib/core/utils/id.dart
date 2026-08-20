import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Short, collision-safe id used for every timeline entity.
String newId() => _uuid.v4().substring(0, 12);
