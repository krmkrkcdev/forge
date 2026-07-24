import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:forge/src/commands/doctor_command.dart';
import 'package:forge/src/commands/fix_command.dart';
import 'package:forge/src/commands/new_command.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'forge',
    'Flutter uygulamalarını üret, mağazaya hazırla, yayınla.',
  )
    ..addCommand(NewCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(FixCommand());

  try {
    exit(await runner.run(arguments) ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
