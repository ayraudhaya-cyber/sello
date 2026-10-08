/// In-app Help copy. Matches current Sello behaviour. Keep sentences short.
abstract final class SelloHelpContent {
  static const title = 'Help';
  static const subtitle = 'Short answers for everyday work.';

  static const topics = <SelloHelpTopic>[
    SelloHelpTopic(
      id: 'collect-money',
      title: 'How do I collect money?',
      priority: SelloHelpPriority.high,
      audience: SelloHelpAudience.all,
      steps: [
        'Sales Rep: open the order → Record collection.',
        'Or use Quick actions → Receive Payment to collect against several orders.',
        'Owner / Manager: open Payments → Receive Payment.',
        'Select the customer.',
        'Tick the orders or opening balance, or Select all.',
        'Enter the amount.',
        'Choose Cash, Card, Bank, or Wallet. For a cheque, use Record collection on the order, or Payments → Cheques.',
        'Save.',
      ],
      notes: [
        'Outstanding goes down when the payment is completed.',
        'If you see Pending Review, wait for the Owner or Manager to approve. Outstanding does not change until then.',
      ],
    ),
    SelloHelpTopic(
      id: 'outstanding-after-order',
      title: 'Why did Outstanding not go up after my order?',
      priority: SelloHelpPriority.high,
      audience: SelloHelpAudience.all,
      steps: [
        'Submitting an order saves it as Placed.',
        'It does not add the amount to Outstanding yet.',
        'Outstanding goes up when goods are delivered.',
        'Open the order and check Delivery: Ordered, Delivered, Remaining.',
        'If Remaining is not zero, record delivery (or ask the Owner if Sales Reps cannot).',
      ],
      notes: [
        'Example: customer owed Rs. 2,000. New credit order Rs. 3,000. After submit, Outstanding is still Rs. 2,000. After delivery, it becomes Rs. 5,000.',
      ],
    ),
    SelloHelpTopic(
      id: 'wrong-sales-rep',
      title: 'Wrong Sales Rep on an order',
      priority: SelloHelpPriority.high,
      audience: SelloHelpAudience.all,
      steps: [
        'Sello cannot change the Sales Rep on an order.',
        'The order keeps the person who was signed in when it was created.',
        'If it is still a Draft, cancel it and create it again on the correct account.',
        'If it is already Placed, tell the Owner. Do not collect the same money twice.',
      ],
    ),
    SelloHelpTopic(
      id: 'credit-cheque',
      title: 'Credit, Paid today, and cheques',
      priority: SelloHelpPriority.high,
      audience: SelloHelpAudience.sales,
      steps: [
        'Paid today: collect money after you submit.',
        'Credit: customer pays later. Outstanding updates when goods are delivered.',
        'Cheque received: the order is saved unpaid. You may record the cheque next, or skip and record it later from the order.',
        'Cheque later: only a note. No cheque is created until you record it.',
        'Arrange later: collect from the order another time.',
      ],
    ),
    SelloHelpTopic(
      id: 'sales-cheque-in-hub',
      title: 'Where does a Sales Rep cheque go?',
      priority: SelloHelpPriority.high,
      audience: SelloHelpAudience.hub,
      steps: [
        'Open Payments, then the Cheques tab.',
        'The cheque appears by itself. Do not add it again.',
        'Waiting to receive: you do not have the paper cheque yet. Outstanding does not change.',
        'In hand: you have the cheque. Outstanding may go down, or wait for approval.',
        'Use Add existing cheque only for old cheques from before Sello.',
      ],
    ),
    SelloHelpTopic(
      id: 'existing-cheque',
      title: 'What is Add existing cheque?',
      priority: SelloHelpPriority.high,
      audience: SelloHelpAudience.hub,
      steps: [
        'It is a history note for a cheque from before Sello.',
        'It does not change Outstanding.',
        'It does not create a payment.',
        'Only Owner or Manager can add one.',
        'For a new cheque, use Record cheque.',
      ],
    ),
    SelloHelpTopic(
      id: 'outstanding-vs-credit',
      title: 'Outstanding vs Credit owing',
      priority: SelloHelpPriority.medium,
      audience: SelloHelpAudience.hub,
      steps: [
        'Outstanding is everyone who still owes money.',
        'Credit owing is the part of that total for customers allowed to buy on credit.',
        'Wallet is separate: extra credit sitting on the customer’s account.',
      ],
    ),
    SelloHelpTopic(
      id: 'opening-balance',
      title: 'Opening balance',
      priority: SelloHelpPriority.medium,
      audience: SelloHelpAudience.hub,
      steps: [
        'This is money the customer already owed.',
        'On a new customer, fill Opening balance when you add them.',
        'Later, open the customer and choose Add opening balance.',
        'It increases Outstanding. It does not create an invoice.',
        'Collect it in Receive payment like any other unpaid item.',
      ],
    ),
    SelloHelpTopic(
      id: 'offline',
      title: 'Working without internet',
      priority: SelloHelpPriority.medium,
      audience: SelloHelpAudience.sales,
      steps: [
        'A visit start and finish can wait on this device.',
        'The order basket is saved on this device.',
        'Submitting an order, collecting money, and recording a cheque need internet.',
      ],
    ),
    SelloHelpTopic(
      id: 'delivery-stock',
      title: 'Delivery and stock',
      priority: SelloHelpPriority.medium,
      audience: SelloHelpAudience.all,
      steps: [
        'Submit order does not reduce stock.',
        'Record delivery reduces stock and updates Outstanding for unpaid goods.',
        'Ordering above available stock is allowed only if the Owner turned that setting on.',
      ],
    ),
  ];
}

enum SelloHelpPriority { high, medium, low }

enum SelloHelpAudience { all, sales, hub }

class SelloHelpTopic {
  const SelloHelpTopic({
    required this.id,
    required this.title,
    required this.priority,
    required this.audience,
    required this.steps,
    this.notes = const [],
  });

  final String id;
  final String title;
  final SelloHelpPriority priority;
  final SelloHelpAudience audience;
  final List<String> steps;
  final List<String> notes;
}
