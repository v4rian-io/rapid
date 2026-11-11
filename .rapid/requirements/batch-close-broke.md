# feature/batch-close-broke

A failed close keeps the batch, names the first batch merge whose tree fails, so the fix lands as one more branch before the next close.

Test: merge-tree-gate
