# feature/one-push-guard

A batch is exactly one push: while a batch is open the pre-push hook refuses every push except the one its close sends; a branch push runs no gate.

Test: batch-one-push
