import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Text field with an optional leading icon and a soft "filled" look that
/// matches the rest of the design system.
class AkashaTextField extends StatelessWidget {
  const AkashaTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.icon,
    this.maxLines = 1,
    this.minLines,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.validator,
    this.onChanged,
    this.suffix,
    this.autofocus = false,
    this.enabled = true,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength,
    this.helperText,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final int maxLines;
  final int? minLines;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final bool autofocus;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      minLines: obscure ? 1 : minLines,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: onChanged,
      autofocus: autofocus,
      enabled: enabled,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      maxLength: maxLength,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.darkText,
        height: 1.4,
      ),
      cursorColor: AppColors.primaryPink,
      cursorRadius: const Radius.circular(2),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        counterText: '',
        prefixIcon: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(icon, size: 19, color: AppColors.lavender),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix,
      ),
    );
  }
}
