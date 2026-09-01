import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/visits/visit_gps_service.dart';
import 'package:sello/shared/data/sri_lanka_areas.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Minimal walk-in registration — only when the buyer decides to purchase.
///
/// Keeps the database clean: no customer row until this sheet succeeds.
class WalkInCustomerSheet extends StatefulWidget {
  const WalkInCustomerSheet({super.key});

  /// Returns [CustomerUpsertInput] or null if cancelled.
  static Future<CustomerUpsertInput?> show(BuildContext context) {
    return showModalBottomSheet<CustomerUpsertInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const WalkInCustomerSheet(),
    );
  }

  @override
  State<WalkInCustomerSheet> createState() => _WalkInCustomerSheetState();
}

class _WalkInCustomerSheetState extends State<WalkInCustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _phone = TextEditingController();
  final _contactPerson = TextEditingController();
  String _area = '';
  List<String> _areaSuggestions = SriLankaAreas.suggestionsNear();
  bool _locatingArea = true;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadNearbyAreas);
  }

  @override
  void dispose() {
    _businessName.dispose();
    _phone.dispose();
    _contactPerson.dispose();
    super.dispose();
  }

  Future<void> _loadNearbyAreas() async {
    final gps = await VisitGpsService.captureOnce(
      timeout: const Duration(seconds: 5),
    );
    if (!mounted) return;
    setState(() {
      _areaSuggestions = SriLankaAreas.suggestionsNear(
        latitude: gps?.latitude,
        longitude: gps?.longitude,
      );
      _locatingArea = false;
    });
  }

  void _submit() {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final contact = _contactPerson.text.trim();
    final area = _area.trim();
    final notes = [
      if (contact.isNotEmpty) 'Contact: $contact',
      if (area.isNotEmpty) 'Area: $area',
      'Registered as walk-in during field visit',
    ].join('\n');

    Navigator.of(context).pop(
      CustomerUpsertInput(
        name: _businessName.text.trim(),
        phone: PhoneNumber.normalizeStorage(_phone.text),
        city: area.isEmpty ? null : area,
        notes: notes,
        customerType: CustomerType.retail,
        creditAllowed: false,
        creditLimit: 0,
        openingBalance: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineSubtle,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Who is buying?',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Only needed because they want to purchase. '
              'We will not save a customer if you cancel.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            SelloTextField(
              controller: _businessName,
              label: 'Business name',
              required: true,
              hint: 'Shop or business name',
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Business name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SelloTextField(
              controller: _phone,
              label: 'Phone number',
              required: true,
              hint: 'Mobile or landline',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  PhoneNumber.validator(value, required: true),
            ),
            const SizedBox(height: 12),
            SelloTextField(
              controller: _contactPerson,
              label: 'Contact person',
              hint: 'Who you spoke with',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            SelloAutocompleteField(
              value: _area,
              suggestions: _areaSuggestions,
              onChanged: (value) => setState(() => _area = value),
              label: 'Area / suburb',
              hint: _locatingArea
                  ? 'Finding nearby areas…'
                  : 'Search or type an area',
              maxSuggestions: 18,
              optionsViewOpenDirection: OptionsViewOpenDirection.up,
            ),
            const SizedBox(height: 20),
            SelloButton(label: 'Save & continue sale', onPressed: _submit),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel — discard this sale'),
            ),
          ],
        ),
      ),
    );
  }
}
