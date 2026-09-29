import 'package:flutter/material.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/services/marketplace_service.dart';

Future<void> showJobChatSheet({
  required BuildContext context,
  required String requestId,
  required String currentUid,
  required String currentName,
  required MarketplaceRepository repository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => JobChatSheet(
      requestId: requestId,
      currentUid: currentUid,
      currentName: currentName,
      repository: repository,
    ),
  );
}

class JobChatSheet extends StatefulWidget {
  const JobChatSheet({
    required this.requestId,
    required this.currentUid,
    required this.currentName,
    required this.repository,
    super.key,
  });

  final String requestId;
  final String currentUid;
  final String currentName;
  final MarketplaceRepository repository;

  @override
  State<JobChatSheet> createState() => _JobChatSheetState();
}

class _JobChatSheetState extends State<JobChatSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Job messages',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<JobMessage>>(
              stream: widget.repository.watchMessages(widget.requestId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Could not load messages.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? const <JobMessage>[];
                if (messages.isEmpty) {
                  return const Center(child: Text('Start the conversation.'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isMine = message.senderUid == widget.currentUid;
                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMine)
                              Text(
                                message.senderName,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            Text(message.text),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.repository.sendMessage(
        requestId: widget.requestId,
        senderUid: widget.currentUid,
        senderName: widget.currentName,
        text: text,
      );
      _controller.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
