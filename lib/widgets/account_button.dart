import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/account_screen.dart';

class AccountButton extends StatefulWidget {
  const AccountButton({super.key});

  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    return IconButton(
      icon: user != null
          ? CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF4FC3F7),
              child: Text(
                user.initials,
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : const Icon(Icons.person_outline, color: Colors.grey),
      tooltip: user != null ? user.displayName : 'Sign in',
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountScreen()),
        );
        // Rebuild after returning from account screen (auth state may have changed)
        if (mounted) setState(() {});
      },
    );
  }
}
