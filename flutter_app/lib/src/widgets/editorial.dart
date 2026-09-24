import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EditorialEyebrow extends StatelessWidget {
  const EditorialEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.25,
            ),
      );
}

class EditorialAppTitle extends StatelessWidget {
  const EditorialAppTitle(this.title,
      {this.eyebrow = 'NOTES / ECOSISTEMA', super.key});
  final String title;
  final String eyebrow;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (MediaQuery.textScalerOf(context).scale(1) <= 1.3)
            EditorialEyebrow(eyebrow),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontFamily: 'serif')),
        ],
      );
}

class EditorialSection extends StatelessWidget {
  const EditorialSection(this.title, {this.detail, super.key});
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (detail != null)
              Text(detail!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

String editorialDate(int millis) => DateFormat('d MMM yyyy', 'it_IT')
    .format(DateTime.fromMillisecondsSinceEpoch(millis));
