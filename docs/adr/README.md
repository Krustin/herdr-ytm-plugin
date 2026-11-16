# Decision records

Durable, dated decision capture: MADR-lite records, one decision per file.
Numbering: read the highest existing number, add 1.

| # | Decision | Status |
|---|---|---|
| [0001](0001-floating-player-in-private-tmux.md) | Floating player runs ytm in a private tmux server | accepted |
| [0002](0002-control-ytm-only-through-its-cli.md) | Control ytm only through its CLI | accepted |

## Format (MADR-lite)
```
# NNNN. <title>
Status: proposed | accepted | superseded
Context: <what forced the decision>
Decision: <what we chose>
Consequences: <trade-offs, what this closes/opens>
```
