import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shooting_companion/helpers/connectivity_helper.dart';

class ConnectivityMonitor extends StatefulWidget {
  final Widget child;

  const ConnectivityMonitor({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  _ConnectivityMonitorState createState() => _ConnectivityMonitorState();
}

class _ConnectivityMonitorState extends State<ConnectivityMonitor> {
  final ConnectivityHelper _connectivityHelper = ConnectivityHelper();
  bool _wasOffline = false;

  @override
  void dispose() {
    _connectivityHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _connectivityHelper.onConnectionChange,
      builder: (context, snapshot) {
        final isOffline = snapshot.data == false;

        if (isOffline && !_wasOffline) {
          _wasOffline = true;
          SchedulerBinding.instance.addPostFrameCallback((_) {
            ConnectivityHelper.showNoInternetSnackBar(context);
          });
        } else if (!isOffline) {
          _wasOffline = false;
        }

        return widget.child;
      },
    );
  }
}
