# Ownership and permissions

In the initial release, only one writer may work in a worktree. Count Root as a writer.
Explorer, Researcher, and Reviewer do not edit. Verifier writes only to its artifact allowlist.
Future paths, generated output, and destinations are also ownership concerns. Treat paths differing only by Windows case as the same path.
Reject deployment through junctions, symlinks, or hard links; inspect the actual target and return to Root.
This is not an OS sandbox that prevents other concurrent processes from replacing links, so stop other edits during deployment.
Root exclusively owns configuration, public contracts, dependencies, lockfiles, and shared Git state.
Children do not change Git staging, branches, or history. Do not reset an out-of-scope change when it is detected.

Verifier uses an isolated writable area and source hashes before and after execution. Return the contract to Root before a build that requires source generation.
Measure the effects of parent sandbox or approval overrides in a fixture; do not report enforcement based only on a setting name.
Isolated worktrees, multiple writers, and automatic machine-wide locks are future work. A worktree is not a sandbox.
