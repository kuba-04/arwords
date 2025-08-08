class PurchaseUpdate {
  final PurchaseUpdateStatus status;
  final String message;
  final dynamic error;

  PurchaseUpdate({required this.status, required this.message, this.error});
}

enum PurchaseUpdateStatus { pending, purchased, error }
