# feature/batch-close

One close tests the final tree of the batch once, verifies every merge on its own tree by a cheap gate, sends one atomic push; a failed close keeps the batch.

Test: batch-land
