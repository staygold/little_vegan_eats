// lib/lists/shopping_item_add_sheet.dart
import 'package:flutter/material.dart';
import 'shopping_repo.dart';

class ShoppingItemAddSheet extends StatefulWidget {
  final String listId;

  const ShoppingItemAddSheet({super.key, required this.listId});

  static Future<void> show(BuildContext context, String listId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ShoppingItemAddSheet(listId: listId),
    );
  }

  @override
  State<ShoppingItemAddSheet> createState() => _ShoppingItemAddSheetState();
}

class _ShoppingItemAddSheetState extends State<ShoppingItemAddSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(); // Or dropdown if you prefer
  
  String _selectedSection = 'Pantry'; // Default
  bool _saving = false;

  final _sections = ['Fresh', 'Pantry', 'Chilled & Frozen', 'Other'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    
    try {
      await ShoppingRepo.instance.addItem(
        listId: widget.listId,
        name: name,
        amount: _amountCtrl.text.trim(),
        unit: _unitCtrl.text.trim(),
        section: _selectedSection,
      );
      if(!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add Item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          
          // Name
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Item Name',
              hintText: 'e.g. Olive Oil',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          // Amount & Unit Row
          Row(
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: 'e.g. 1',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Unit (Optional)',
                    hintText: 'e.g. bottle, kg',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Section Dropdown
          DropdownButtonFormField<String>(
            value: _selectedSection,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: _sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _selectedSection = v!),
          ),
          const SizedBox(height: 24),

          // Save Button
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add Item'),
          ),
        ],
      ),
    );
  }
}