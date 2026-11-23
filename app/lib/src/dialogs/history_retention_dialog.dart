import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:filemanager/l10n/app_localizations.dart';

Future<int?> showHistoryRetentionDialog(
  BuildContext context, {
  required int currentDays,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _HistoryRetentionDialog(currentDays: currentDays),
  );
}

class _HistoryRetentionDialog extends StatefulWidget {
  final int currentDays;

  const _HistoryRetentionDialog({required this.currentDays});

  @override
  State<_HistoryRetentionDialog> createState() =>
      _HistoryRetentionDialogState();
}

class _HistoryRetentionDialogState extends State<_HistoryRetentionDialog> {
  static const List<int> _presets = [0, 7, 14, 30, 90, 365];

  late final TextEditingController _controller = TextEditingController(
    text: '${widget.currentDays < 0 ? 0 : widget.currentDays}',
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(int days) {
    setState(() {
      _controller.text = '$days';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _errorText = null;
    });
  }

  void _submit(AppLocalizations l10n) {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0 || parsed > 36500) {
      setState(() => _errorText = l10n.historyRetentionInvalidInput);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedValue = int.tryParse(_controller.text.trim());

    return AlertDialog(
      title: Text(l10n.historyRetentionTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.historyRetentionDesc,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in _presets)
                  ChoiceChip(
                    key: ValueKey('history_retention_preset_$days'),
                    label: Text(
                      days == 0
                          ? l10n.historyRetentionDisabledShort
                          : l10n.historyRetentionDaysShort(days),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: selectedValue == days,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _selectPreset(days),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('history_retention_input'),
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.historyRetentionInputLabel,
                errorText: _errorText,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {
                if (_errorText != null) _errorText = null;
              }),
              onSubmitted: (_) => _submit(l10n),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => _submit(l10n),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
