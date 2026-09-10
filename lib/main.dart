import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const HomeTunnelHostApp());
}

class HomeTunnelHostApp extends StatelessWidget {
  const HomeTunnelHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeTunnel Host Node',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.greenAccent,
      ),
      home: const HostHomePage(),
    );
  }
}

class HostHomePage extends StatefulWidget {
  const HostHomePage({super.key});

  @override
  State<HostHomePage> createState() => _HostHomePageState();
}

class _HostHomePageState extends State<HostHomePage> {
  static const platform = MethodChannel('co.ke.hometunnel/wireguard_host');

  final String _backendUrl = "https://hometunnel-backend-render.onrender.com";

  String _pairCode = "------";
  bool _isHosting = false;
  String _statusMessage = "Node Offline";
  
  String _hostPrivateKey = "";
  String _hostPublicKey = "";

  @override
  void initState() {
    super.initState();
    _generateKeys();
  }

  void _generateKeys() {
    final Random random = Random.secure();
    final privBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final pubBytes = List<int>.generate(32, (i) => random.nextInt(256));
    
    _hostPrivateKey = base64Encode(privBytes);
    _hostPublicKey = base64Encode(pubBytes);
  }

  String _generateRandom6DigitCode() {
    final Random random = Random();
    int number = random.nextInt(900000) + 100000;
    return number.toString();
  }

  Future<void> _startHostNode() async {
    final newCode = _generateRandom6DigitCode();

    setState(() {
      _statusMessage = "Registering Node on Render...";
      _pairCode = newCode;
    });

    try {
      // 1. Wake up Render
      await http.get(Uri.parse(_backendUrl)).timeout(const Duration(seconds: 15));

      // 2. Register Host Node with Backend
      final registerResponse = await http.post(
        Uri.parse("$_backendUrl/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "code": newCode,
          "role": "host",
          "nodePublicKey": _hostPublicKey,
          "nodeEndpoint": "102.210.80.12:51820" // Replace or auto-detect public endpoint
        }),
      ).timeout(const Duration(seconds: 15));

      if (registerResponse.statusCode == 200 || registerResponse.statusCode == 201) {
        // 3. Start local WireGuard host service
        await _startWireGuardHostServer();

        setState(() {
          _isHosting = true;
          _statusMessage = "Node Active! Waiting for Client...";
        });
      } else {
        setState(() {
          _statusMessage = "Registration failed. Try again.";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Error connecting to signaling server.";
      });
    }
  }

  Future<void> _startWireGuardHostServer() async {
    final wgHostConfig = '''
[Interface]
PrivateKey = $_hostPrivateKey
Address = 10.200.0.1/24
ListenPort = 51820

[Peer]
PublicKey = CLIENT_PUBLIC_KEY
AllowedIPs = 10.200.0.2/32
''';

    try {
      await platform.invokeMethod('startHostServer', {'config': wgHostConfig});
    } on PlatformException catch (e) {
      // Graceful fallback if testing on a device without root/server mode
      debugPrint("Host WireGuard notice: ${e.message}");
    }
  }

  Future<void> _stopHostNode() async {
    try {
      await platform.invokeMethod('stopHostServer');
    } catch (_) {}

    setState(() {
      _isHosting = false;
      _pairCode = "------";
      _statusMessage = "Node Offline";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeTunnel Host Node'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _isHosting ? Icons.router : Icons.phonelink_off,
              size: 80,
              color: _isHosting ? Colors.greenAccent : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isHosting ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text("Pairing Code", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    _pairCode,
                    style: const TextStyle(
                      fontSize: 36,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (!_isHosting)
              ElevatedButton(
                onPressed: _startHostNode,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.greenAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Start Host Node', style: TextStyle(fontSize: 18, color: Colors.black)),
              )
            else
              ElevatedButton(
                onPressed: _stopHostNode,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Stop Host Node', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
