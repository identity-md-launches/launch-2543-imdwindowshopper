# IMDwindowshopper (WWW)

An immutable, fixed-supply ERC-20 built with vendored OpenZeppelin Contracts 5.0.2.

| Parameter | Value |
| --- | --- |
| Solidity contract | `src/IMDwindowshopper.sol:IMDwindowshopper` |
| Token name | `IMDwindowshopper` |
| Symbol | `WWW` |
| Decimals | `18` |
| Supply | `1,000,000,000 WWW` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Constructor caller (`msg.sender`) |
| Compiler | Solidity `0.8.26`, Cancun EVM |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The constructor makes one mint and emits `Transfer(address(0), deployer, 10^27)`.
There is no callable mint or burn function, so total supply remains constant.

## Behavior and assumptions

The brief specifies a standard token, so transfers move the exact requested amount.
There are no transfer fees, taxes, rebases, account restrictions, or transfer hooks.
Transfers and approvals follow OpenZeppelin ERC-20 behavior, including zero-amount
transfers, self-transfers, and rejection of zero recipients and zero spenders.
Failed operations revert with ERC-6093 custom errors and roll back every change.

`approve` replaces the current allowance. `transferFrom` requires an allowance even
when the caller is the holder, reduces finite allowances, and leaves an allowance of
`type(uint256).max` unchanged. Zero-amount delegated transfers between valid addresses
are permitted with zero allowance. OpenZeppelin 5 does not emit a new `Approval`
event when `transferFrom` spends an allowance; integrations should read `allowance`.

The token has no owner, administrator, pause, seizure, blacklist, upgrade, or
initialization mechanism. Its constructor calls no outside contract. The inherited
mint/burn helpers are internal; this contract exposes neither after construction.

## Build and check

Run at the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0265c7ea194e51d27120fc5d08f7d01e63198fc050ee80ecefdce11292e78c3a forge test
forge fmt --check
```

The Solidity dependency is included under `lib/openzeppelin-contracts`, with its
license and provenance. No package install, environment variables, network RPC,
filesystem permissions, or FFI are required by the tests. The fuzz seed above is
the assignment's reproducible test seed; tests do not read or change the environment.

Tests check metadata, exact supply, the mint event, contract-factory deployment,
full-value distribution and claims, transfers and approval events, allowance
consumption/revocation, unauthorized spending, failed-operation rollback, zero and
maximum values, and absence of minting and administrative entrypoints. Six fuzz
tests cover transfer accounting, self-transfers, invalid amounts, delegated transfers,
and conservation through sequences of 32 transfers. Each test deploys a fresh token.

## Deployment and operations

The intended launch chain is Ethereum (chain ID 1). Deploy the compiled contract
directly with no arguments and no ETH. On the IMD launch, the factory is the
constructor caller and receives **all** `10^27` base units. A direct deployment from
another account would give that account the entire supply instead. There is no
owner parameter or post-deployment initialization.

IMD's separate launch process is responsible for the factory deployment, launch
manifest, swarm distribution, pool setup, and remainder transfer. The factory's
allocation is 10% to the swarm distributor, 70% to liquidity, and 20% to the
requester's remainder recipient, as supplied in the task. These transfers occur
after minting and are not performed by this token's constructor. The launch's pool
fee is separate from token transfers, which have no fee. This repository supplies
the token only; it does not execute a launch or broadcast transactions.

The deployer should verify the source and deployment artifact, check `name`,
`symbol`, `decimals`, `totalSupply`, and the factory's initial balance, and complete
the external launch flow. No token settings or administrative duties remain after
deployment. Holders manage their keys and approvals; use limited approvals and
revoke them when no longer needed. Changing a live allowance can race a spender's
transaction, so consider revoking it to zero before granting a replacement.

Transfers cannot be reversed. Tokens or other assets sent to a contract that cannot
return them may be permanently inaccessible; this token has no asset-rescue
function. ERC-20 transfers make no recipient callbacks, so they cannot validate
that a recipient knows how to return tokens. Normal native-ETH sends are rejected.

The local validation consists of compilation, unit tests, fuzz tests, and a manual
review against the supplied security reference. Slither and Mythril have not been
run. Passing tests is not an independent security audit; the launch process remains
responsible for independent review and post-deployment source verification.
