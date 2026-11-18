import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plexus/blockchain/v2/escrow_api.dart';
import 'package:plexus/blockchain/v2/escrow_payment_flow.dart';
import 'package:plexus/blockchain/v2/escrow_v2_config.dart';
import 'package:plexus/blockchain/v2/escrow_v2_errors.dart';
import 'package:plexus/blockchain/v2/escrow_v2_models.dart';
import 'package:plexus/blockchain/v2/escrow_v2_ports.dart';
import 'package:plexus/blockchain/v2/escrow_v2_service.dart';
import 'package:plexus/blockchain/v2/injected_wallet.dart';
import 'package:plexus/blockchain/v2/wallet_connect_service.dart';
import 'package:plexus/blockchain/v2/web3_chain_reader.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// DEVELOPMENT ONLY. A test bench for the V2 wallet module: connect a wallet, pay a signed quote, and see every step.
///   flutter run -d chrome --web-port 8080 -t lib/main_wallet_test.dart
/// It is not part of the production app and nothing links to it.
class WalletTestPage extends StatefulWidget {
  const WalletTestPage({super.key});

  @override
  State<WalletTestPage> createState() => _WalletTestPageState();
}

class _WalletTestPageState extends State<WalletTestPage> {
  static const _config = EscrowV2Config();
  static const _devQuote = String.fromEnvironment('DEV_QUOTE_JSON');

  final _quoteCtrl = TextEditingController(text: _devQuote);
  final _events = <String>[];
  late final Web3ChainReader _reader = Web3ChainReader(_config);
  late final WalletConnectService _wc = WalletConnectService(config: _config);
  late final InjectedWalletService _injected = InjectedWalletService(config: _config);

  TxSender? _sender;
  String? _wcUri;
  String _balance = '-';
  bool _busy = false;
  SignedQuote? _lastQuote;
  String _order = '-';

  @override
  void dispose() {
    _quoteCtrl.dispose();
    _reader.dispose();
    super.dispose();
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() => _events.insert(0, '${TimeOfDay.now().format(context)}  $line'));
  }

  String _fmt(BigInt v) => (v / BigInt.from(10).pow(16)).toInt().toString().padLeft(3, '0').replaceAllMapped(RegExp(r'(\d+)(\d{2})$'), (m) => '${m[1]}.${m[2]}');

  Future<void> _refreshBalance() async {
    final a = _sender?.address;
    if (a == null) return;
    try {
      final b = await _reader.tokenBalance(a);
      setState(() => _balance = '${_fmt(b)} USDT');
    } catch (e) {
      _log('Could not read the balance: ${interpretError(e).message}');
    }
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on EscrowException catch (e) {
      _log('ERROR ${e.code}: ${e.message}');
    } catch (e) {
      _log('ERROR ${interpretError(e).code}: ${interpretError(e).message}  ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectBrowserWallet() => _guard(() async {
        final a = await _injected.connect();
        _sender = _injected;
        _log('Browser wallet connected: $a on ${_config.chainName}');
        await _refreshBalance();
      });

  Future<void> _connectWalletConnect() => _guard(() async {
        _wc.onConnected = () {
          _sender = _wc;
          _log('WalletConnect wallet connected: ${_wc.address}');
          setState(() => _wcUri = null);
          _refreshBalance();
        };
        final uri = await _wc.startPairing();
        if (uri != null) {
          setState(() => _wcUri = uri);
          _log('Scan the QR code (or paste the link) in your wallet app.');
        }
      });

  EscrowV2Service _service() => EscrowV2Service(config: _config, sender: _sender!, reader: _reader);

  Future<void> _pay() => _guard(() async {
        final sender = _sender;
        if (sender == null) throw const EscrowException('NOT_CONNECTED', 'Connect a wallet first.');
        final SignedQuote quote;
        try {
          quote = SignedQuote.fromJson(jsonDecode(_quoteCtrl.text) as Map<String, dynamic>);
        } catch (e) {
          throw const EscrowException('BAD_QUOTE', 'Paste the quote JSON printed by "npm run quote:testnet" first.');
        }
        _lastQuote = quote;
        _log('Paying ${quote.total / BigInt.from(10).pow(18)} USDT for order ${quote.orderRef.substring(0, 10)}…');
        final flow = EscrowPaymentFlow(service: _service(), api: DevQuoteApi(jsonEncode(quote.toJson())));
        final outcome = await flow.payOrder('dev', onStep: (s) => _log('step: ${s.name}'));
        if (outcome.result.approveTx != null) _log('approve tx   ${_scan(outcome.result.approveTx!)}');
        _log('PAID. create order tx   ${_scan(outcome.result.createOrderTx)}');
        await _refreshBalance();
        await _refreshOrder();
      });

  /// Reads the order of the quote in the box from the chain: its status and any delivery fee change waiting for the buyer.
  Future<void> _refreshOrder() async {
    String? ref = _lastQuote?.orderRef;
    if (ref == null) {
      try {
        ref = SignedQuote.fromJson(jsonDecode(_quoteCtrl.text) as Map<String, dynamic>).orderRef;
      } catch (_) {
        return;
      }
    }
    try {
      final o = await _reader.order(ref);
      if (!mounted) return;
      setState(() => _order = o == null
          ? 'not on the blockchain yet'
          : '${o.statusName}  |  delivery ${_fmt(o.deliveryAmount)} USDT'
              '${o.status == OrderInfo.adjustmentProposed ? '  |  seller proposes ${_fmt(o.proposedDelivery)} USDT (you would pay ${_fmt(o.extraToPay)} more)' : ''}');
    } catch (e) {
      _log('Could not read the order: ${interpretError(e).message}');
    }
  }

  String _scan(String hash) => '${_config.chainId == 97 ? 'https://testnet.bscscan.com' : 'https://bscscan.com'}/tx/$hash';

  Future<void> _action(String label, Future<String> Function(EscrowV2Service s, SignedQuote q) run) => _guard(() async {
        final q = _lastQuote ?? SignedQuote.fromJson(jsonDecode(_quoteCtrl.text) as Map<String, dynamic>);
        if (_sender == null) throw const EscrowException('NOT_CONNECTED', 'Connect a wallet first.');
        _log('$label: waiting for the wallet…');
        final tx = await run(_service(), q);
        _log('$label done   ${_scan(tx)}');
        await _refreshBalance();
        await _refreshOrder();
      });

  @override
  Widget build(BuildContext context) {
    final connected = _sender?.isConnected == true;
    return Scaffold(
      appBar: AppBar(title: const Text('PLEXUS V2 wallet test bench (development only)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText('Network: ${_config.chainName} (chain ${_config.chainId})\nEscrow: ${_config.escrowAddress}\nToken (test USDT): ${_config.tokenAddress}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: _busy || !InjectedWalletService.isAvailable ? null : _connectBrowserWallet,
              child: Text(InjectedWalletService.isAvailable ? 'Connect browser wallet (MetaMask)' : 'No browser wallet found'),
            ),
            OutlinedButton(onPressed: _busy ? null : _connectWalletConnect, child: const Text('Connect with WalletConnect (QR)')),
          ]),
          if (_wcUri != null) ...[
            const SizedBox(height: 12),
            Center(child: QrImageView(data: _wcUri!, size: 220, backgroundColor: Colors.white)),
            Row(children: [
              Expanded(child: SelectableText(_wcUri!, maxLines: 2)),
              IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _wcUri!))),
            ]),
          ],
          const SizedBox(height: 12),
          Text(connected ? 'Connected: ${_sender!.address}\nBalance: $_balance' : 'Not connected',
              style: TextStyle(fontWeight: FontWeight.bold, color: connected ? Colors.green[800] : Colors.red[800])),
          const SizedBox(height: 12),
          TextField(
            controller: _quoteCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Signed quote JSON (from: npm run quote:testnet)'),
          ),
          const SizedBox(height: 8),
          SelectableText('Order on the blockchain: $_order', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: _busy || !connected ? null : _pay, child: const Text('Pay this quote')),
            OutlinedButton(onPressed: _busy ? null : _refreshOrder, child: const Text('Refresh order')),
            FilledButton.tonal(
                onPressed: _busy || !connected
                    ? null
                    : () => _action('Accept delivery change', (s, q) => s.acceptDeliveryAdjustmentForOrder(q.orderRef)),
                child: const Text('Accept delivery change')),
            FilledButton.tonal(
                onPressed: _busy || !connected
                    ? null
                    : () => _action('Decline delivery change', (s, q) => s.declineDeliveryAdjustment(q.orderRef)),
                child: const Text('Decline delivery change')),
            OutlinedButton(onPressed: _busy || !connected ? null : _refreshBalance, child: const Text('Refresh balance')),
            OutlinedButton(
                onPressed: _busy || !connected ? null : () => _action('Confirm receipt', (s, q) => s.confirmReceipt(q.orderRef)),
                child: const Text('Confirm receipt')),
            OutlinedButton(
                onPressed: _busy || !connected ? null : () => _action('Open dispute', (s, q) => s.openDispute(q.orderRef, 'test dispute')),
                child: const Text('Open dispute')),
            OutlinedButton(
                onPressed: _busy || !connected ? null : () => _action('Withdraw refund', (s, q) => s.withdrawRefund()),
                child: const Text('Withdraw refund')),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          const Divider(height: 32),
          const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final e in _events) SelectableText(e, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }
}
