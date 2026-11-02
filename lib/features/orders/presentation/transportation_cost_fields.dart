import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/shared/models/transportation_payer.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Transportation amount and who pays. Optional. Seller pays is the default.
class TransportationCostFields extends StatelessWidget {
  const TransportationCostFields({
    super.key,
    required this.amountController,
    required this.payer,
    required this.onPayerChanged,
    this.onAmountChanged,
  });

  final TextEditingController amountController;
  final TransportationPayer payer;
  final ValueChanged<TransportationPayer> onPayerChanged;
  final ValueChanged<String>? onAmountChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloTextField(
          controller: amountController,
          label: 'Transportation',
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          onChanged: onAmountChanged,
        ),
        const SizedBox(height: 12),
        SelloDropdown<TransportationPayer>(
          label: 'Who pays transportation',
          value: payer,
          items: [
            for (final option in TransportationPayer.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value != null) onPayerChanged(value);
          },
        ),
      ],
    );
  }
}
