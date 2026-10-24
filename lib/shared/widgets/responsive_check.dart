import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';

import '../../landing_page.dart';

class ResponsiveCheck extends StatelessWidget {
  const ResponsiveCheck({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMobil = ResponsiveBreakpoints.of(context).isMobile;

    if(isMobil){
      return child;
    }
    return LandingPage();
  }
}