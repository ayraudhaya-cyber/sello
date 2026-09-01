/// Canonical route path constants.
abstract final class RoutePaths {
  static const String splash = '/';
  static const String login = '/login';
  static const String onboarding = '/onboarding';

  /// Post-login first-time Owner workspace setup (not signup).
  static const String ownerSetup = '/setup';

  // Sello (sales)
  static const String sello = '/sello';
  static const String selloDashboard = '/sello/dashboard';
  static const String selloCustomers = '/sello/customers';
  static const String selloProducts = '/sello/products';
  static const String selloInventory = '/sello/inventory';
  static const String selloOrders = '/sello/orders';
  static const String selloProfile = '/sello/profile';
  static const String selloVisit = '/sello/visit';

  // Hub — order matches HTML nav (flat index for shell branches)
  static const String hub = '/hub';
  static const String hubDashboard = '/hub/dashboard';
  static const String hubReports = '/hub/reports';
  static const String hubOrders = '/hub/orders';
  static const String hubInventory = '/hub/inventory';
  static const String hubProducts = '/hub/products';
  static const String hubSuppliers = '/hub/suppliers';
  static const String hubCustomers = '/hub/customers';
  static const String hubPayments = '/hub/payments';
  static const String hubSchedule = '/hub/schedule';
  static const String hubVisits = '/hub/visits';
  static const String hubEmployees = '/hub/employees';
  static const String hubAttendance = '/hub/attendance';
  static const String hubSettings = '/hub/settings';

  /// Public token-gated order/invoice document (no session required).
  static const String orderDocument = '/d';

  /// Soft alias — redirects to reports.
  static const String hubAnalytics = '/hub/analytics';
}
