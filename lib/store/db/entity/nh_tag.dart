import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'nh_tag.g.dart';

@CopyWith()
@JsonSerializable()
class NhTag {
  NhTag({
    required this.id,
    this.name,
    this.count,
    this.type,
    this.lastUseTime = 0,
    this.translateName,
  });

  factory NhTag.fromJson(Map<String, Object?> json) => _$NhTagFromJson(json);
  Map<String, dynamic> toJson() => _$NhTagToJson(this);

  int id;

  @JsonKey(includeFromJson: false, includeToJson: false)
  String? type;

  String? name;
  String? translateName;
  int? count;
  int lastUseTime;

  @override
  String toString() {
    return 'NhTag{id: $id, type: $type, name: $name, translateName: $translateName, count: $count, lastUseTime: $lastUseTime}';
  }
}
