import 'package:equatable/equatable.dart';

/// Domain role row from `public.roles`.
class Role extends Equatable {
  const Role({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.displayOrder = 0,
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final int displayOrder;

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, code, name, description, displayOrder];
}
