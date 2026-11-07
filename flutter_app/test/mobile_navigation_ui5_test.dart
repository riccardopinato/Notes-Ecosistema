import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/mobile_navigation_ui5.dart';

void main() {
  test('UI5 five mobile tabs map to existing canonical sections', () {
    expect(MobileNavigationUi5.sections, [0, 1, 3, 2, 4]);
    for (var index = 0; index < 5; index++) {
      final section = MobileNavigationUi5.sectionForDestination(index);
      expect(MobileNavigationUi5.destinationForSection(section), index);
    }
    // Search section remains internally index 5, but highlights Notes.
    expect(MobileNavigationUi5.destinationForSection(5), 1);
    expect(
      () => MobileNavigationUi5.destinationForSection(42),
      throwsRangeError,
    );
  });

  test('five labels preserve six supported locales without hidden buttons', () {
    expect(MobileNavigationUi5.hasAllLocales, isTrue);
    expect(MobileNavigationUi5.title('it', 2), 'Attività');
    expect(MobileNavigationUi5.title('de', 4), 'Räume');
    expect(MobileNavigationUi5.title('xx', 1), 'Notes');
  });
}
