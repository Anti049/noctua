import 'package:freezed_annotation/freezed_annotation.dart';

part 'install_progress.freezed.dart';

enum InstallStage { downloading, installing, done, failed, canceled }

@freezed
abstract class InstallProgress with _$InstallProgress {
  const factory InstallProgress(
    InstallStage stage, {

    /// 0–100 while downloading.
    @Default(0) int percent,
    String? error,
  }) = _InstallProgress;
}
