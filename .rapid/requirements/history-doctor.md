# feature/history-doctor

The history invariants I1 to I9 are checked over every merge at once, one worker per core; doctor reports each broken invariant by name, lists every exception.

Test: parallel-history
