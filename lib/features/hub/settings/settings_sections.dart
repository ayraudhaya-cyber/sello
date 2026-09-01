import 'package:flutter/material.dart';

/// Identifiers for the Settings left-nav. Additive — append new values for
/// future phases without restructuring the screen.
enum SettingsSectionId {
  business,
  branding,
  inventory,
  productFields,
  ordersInvoices,
  notifications,
  reliability,
  appearance,
  company,
  about,
  // Future (keep commented until wired):
  // customers,
  // payments,
  // integrations,
  // ai,
  // pos,
  // printing,
  // receipts,
  permissions,
}

class SettingsSectionSpec {
  const SettingsSectionSpec({
    required this.id,
    required this.label,
    required this.icon,
    this.comingSoon = false,
  });

  final SettingsSectionId id;
  final String label;
  final IconData icon;
  final bool comingSoon;
}

/// Registry of settings sections. Add new entries here as phases ship.
const kSettingsSections = <SettingsSectionSpec>[
  SettingsSectionSpec(
    id: SettingsSectionId.business,
    label: 'Business',
    icon: Icons.apartment_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.branding,
    label: 'Branding',
    icon: Icons.brush_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.inventory,
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.productFields,
    label: 'Product Details',
    icon: Icons.tune_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.ordersInvoices,
    label: 'Orders & Invoices',
    icon: Icons.receipt_long_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.notifications,
    label: 'Notifications',
    icon: Icons.notifications_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.reliability,
    label: 'Reliability',
    icon: Icons.cloud_sync_outlined,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.permissions,
    label: 'Access',
    icon: Icons.admin_panel_settings_outlined,
    comingSoon: true,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.appearance,
    label: 'Appearance',
    icon: Icons.palette_outlined,
    comingSoon: true,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.company,
    label: 'Company',
    icon: Icons.business_outlined,
    comingSoon: true,
  ),
  SettingsSectionSpec(
    id: SettingsSectionId.about,
    label: 'About',
    icon: Icons.info_outline_rounded,
  ),
];
