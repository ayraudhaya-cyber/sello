import 'package:sello/shared/models/customer_summary.dart';

/// Client-side match for name, phone, WhatsApp, code, company, or email.
bool matchesCustomerSearch(CustomerSummary customer, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  bool hit(String? value) =>
      value != null && value.toLowerCase().contains(needle);
  return hit(customer.name) ||
      hit(customer.phone) ||
      hit(customer.whatsapp) ||
      hit(customer.code) ||
      hit(customer.companyName) ||
      hit(customer.email);
}
