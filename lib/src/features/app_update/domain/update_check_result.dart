import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:noctua/src/features/app_update/domain/app_release.dart';

part 'update_check_result.freezed.dart';

/// The result of a check: every release (for the changelog) and the update
/// this device can install, if any.
@freezed
abstract class UpdateCheckResult with _$UpdateCheckResult {
  const factory UpdateCheckResult({required List<AppRelease> releases, required AvailableUpdate? update, required DateTime checkedAt}) =
      _UpdateCheckResult;
}
