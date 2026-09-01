import 'package:equatable/equatable.dart';

/// Operational timeline entry for an order (derived + ledger-backed).
enum OrderTimelineKind {
  created,
  updated,
  submitted,
  completed,
  cancelled,
  stockMoved,
  paymentReceived,
  archived,
  note,
}

class OrderTimelineEvent extends Equatable {
  const OrderTimelineEvent({
    required this.kind,
    required this.title,
    required this.at,
    this.detail,
  });

  final OrderTimelineKind kind;
  final String title;
  final DateTime at;
  final String? detail;

  @override
  List<Object?> get props => [kind, title, at, detail];
}
