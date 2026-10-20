import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_extensions.dart';

/// Dialog owns its controller and returns only a group name.
/// No API call or ScaffoldMessenger lookup happens inside this route.
class TaskGroupDialog extends StatefulWidget {
  const TaskGroupDialog({
    super.key,
    this.initialName,
    this.renameTitle = 'Rename approval group',
    this.createTitle = 'New Group',
    this.fieldLabel = 'Group name',
    this.fieldHint = 'Enter group name...',
    this.createButtonLabel = 'Create group',
    this.maxNameLength = 120,
    this.validateName,
  });

  /// When provided, reuse this visual for the approval group rename flow.
  final String? initialName;
  /// Shared visual for task and approval group rename flows.
  final String renameTitle;
  /// Optional wording and validation to reuse the same visual for Drive folders.
  final String createTitle;
  final String fieldLabel;
  final String fieldHint;
  final String createButtonLabel;
  final int maxNameLength;
  final String? Function(String)? validateName;

  @override
  State<TaskGroupDialog> createState() => _TaskGroupDialogState();
}

class _TaskGroupDialogState extends State<TaskGroupDialog> {
  late final TextEditingController _name;
  String? _error;

  bool get _editing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > widget.maxNameLength) {
      setState(() => _error =
          widget.maxNameLength == 120 && widget.createTitle == 'New Group'
              ? 'მიუთითე ჯგუფის სახელი (მაქს. 120 სიმბოლო)'
              : 'Enter a name (maximum ${widget.maxNameLength} characters)');
      return;
    }
    final validationError = widget.validateName?.call(name);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    // Pop is synchronous, using the *still mounted* dialog context.
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>()!;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: p.cardBorder),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: p.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    height: 8,
                    width: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF89B0FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _editing ? widget.renameTitle : widget.createTitle,
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 18,
                        letterSpacing: -0.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Material(
                    color: p.card,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: SizedBox(
                        height: 33,
                        width: 33,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: p.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: widget.maxNameLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                buildCounter: (
                  context, {
                  required int currentLength,
                  required bool isFocused,
                  required int? maxLength,
                }) => null,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: p.card,
                  labelText: widget.fieldLabel,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  labelStyle: TextStyle(
                    color: p.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  floatingLabelStyle: TextStyle(
                    color: p.link,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  hintText: widget.fieldHint,
                  hintStyle: TextStyle(
                    color: p.hintText,
                    fontSize: 12,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  border: outline,
                  enabledBorder: outline,
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: p.link, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 1.5,
                    ),
                  ),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 5),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _name,
                builder: (context, value, child) => Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${value.text.length}/${widget.maxNameLength}',
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: p.secondaryText,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(23),
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.gradientStart,
                          AppColors.gradientEnd,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _submit,
                        borderRadius: BorderRadius.circular(23),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 19),
                          child: Center(
                            child: Text(
                              _editing ? 'Save' : widget.createButtonLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
