# feature/banned-files

Secrets, keys, builds, archives never enter history: the pre-commit hook refuses them staged, land refuses them in a branch.

Test: banned-and-kept
