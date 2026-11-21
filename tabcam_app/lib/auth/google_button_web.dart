import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// On web, Google requires its own button to sign in: with [icon], its
/// logo alone (the app bar's on a phone).
Widget? googleSignInButton({bool icon = false}) => gsi.renderButton(
  configuration: gsi.GSIButtonConfiguration(
    type: icon ? gsi.GSIButtonType.icon : gsi.GSIButtonType.standard,
    theme: gsi.GSIButtonTheme.filledBlack,
    size: gsi.GSIButtonSize.medium, // Fits the app bar.
    text: gsi.GSIButtonText.signinWith,
    shape: gsi.GSIButtonShape.pill,
  ),
);
