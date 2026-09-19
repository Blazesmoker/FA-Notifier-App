import 'package:material_ui/material_ui.dart';
import 'fur_affinity_settings_styles.dart';

class IosSettingsTextFieldRow extends StatelessWidget {
  const IosSettingsTextFieldRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.controller,
    this.enabled = true,
    this.obscureText = false,
    this.onToggleObscureText,
    this.keyboardType,
    this.maxLength,
    this.autofillHints,
  });

  final String title;
  final String? subtitle;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final VoidCallback? onToggleObscureText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontSize: 16,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(
                color: enabled
                    ? furAffinitySettingsSecondary
                    : Colors.white30,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 9),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLength: maxLength,
            autofillHints: autofillHints,
            cursorColor: furAffinitySettingsAccent,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              filled: true,
              fillColor: furAffinitySettingsField,
              suffixIcon: onToggleObscureText == null
                  ? null
                  : IconButton(
                      onPressed: enabled ? onToggleObscureText : null,
                      tooltip: obscureText ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscureText ? Icons.visibility_off : Icons.visibility,
                        color: enabled
                            ? furAffinitySettingsSecondary
                            : Colors.white30,
                      ),
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(
                  color: furAffinitySettingsAccent,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IosSettingsActionButton extends StatelessWidget {
  const IosSettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: furAffinitySettingsAccent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: furAffinitySettingsAccent.withValues(
              alpha: 0.45,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class SettingsSaveAction extends StatelessWidget {
  const SettingsSaveAction({
    super.key,
    required this.dirty,
    required this.saving,
    required this.onPressed,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: furAffinitySettingsAccent,
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Save changes',
      onPressed: dirty ? onPressed : null,
      icon: Icon(
        Icons.check,
        color: dirty ? furAffinitySettingsAccent : Colors.grey,
      ),
    );
  }
}
