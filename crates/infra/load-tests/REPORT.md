# x402 Batch Settlement: Gas and Batch-Size Report

Date: July 21, 2026

## Summary

The practical default is **100 channel claims per transaction**.

At 100 rows, `claim` costs about 38.2k gas per row and `claimWithSignature` costs about 40.9k. Larger batches do not materially improve gas efficiency. They mostly add calldata, increase retry cost, and leave less room below Base's per-transaction gas cap.

The largest batches measured below Base's 16,777,216 gas limit were:

- **438 rows** for `claim`
- **406 rows** for `claimWithSignature`

Those are measured boundaries, not recommended production sizes. A small change in contract bytecode or calldata byte composition can move the result. For routine settlement, 100 rows offers nearly all of the batching benefit with comfortable headroom.

## What was tested

The tests deployed `x402/contracts/evm/src/x402BatchSettlement.sol` directly from the x402 repository at revision `0a604079aca7b5a45a2e1620ba444e13982646c8`.

The deployment used the repository's normal `contracts/evm/foundry.toml` settings:

- Solidity 0.8.28
- Cancun EVM
- optimizer enabled
- 200 optimizer runs
- `via_ir = false`
- CBOR metadata disabled
- bytecode hash disabled

This is the same bytecode configuration available to a permissionless deployer following the x402 repository setup. No load-test fixture copy was used for the gas measurements.

Each claim row used:

- a distinct funded channel
- a distinct receiver
- an EOA payer authorizer
- an EOA receiver authorizer
- a valid payer-signed cumulative voucher
- the first state-changing claim on that channel

The first claim is the conservative case because it writes channel and receiver accounting from zero to non-zero.

Reported gas includes contract execution, the 21,000 transaction base cost, and calldata gas. It does not include Base's separate L1 data fee.

## Claim batch-size results

| Rows | `claim` gas | Gas/row | `claimWithSignature` gas | Gas/row |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 60,441 | 60,441 | 72,384 | 72,384 |
| 10 | 402,360 | 40,236 | 436,492 | 43,649 |
| 50 | 1,922,753 | 38,455 | 2,058,263 | 41,165 |
| 100 | 3,824,996 | 38,249 | 4,093,402 | 40,934 |
| 150 | 5,729,237 | 38,194 | 6,137,426 | 40,916 |
| 200 | 7,635,992 | 38,179 | 8,190,816 | 40,954 |
| 250 | 9,544,565 | 38,178 | 10,252,922 | 41,011 |
| 300 | 11,455,664 | 38,185 | 12,324,393 | 41,081 |
| 350 | 13,368,761 | 38,196 | 14,404,785 | 41,156 |
| 400 | 15,283,689 | 38,209 | 16,493,859 | 41,234 |
| 450 | 17,200,470 | 38,223 | 18,591,661 | 41,314 |

The first ten rows provide most of the amortization. Gas per row bottoms out around 200–250 rows for `claim`, but the difference from 100 rows is less than 0.2%. `claimWithSignature` reaches its low point around 100–150 rows and then becomes gradually more expensive per row.

`claimWithSignature` has two extra costs:

1. it hashes every row into the receiver-authorizer batch digest;
2. it verifies the receiver-authorizer signature.

The second cost is fixed, but the first scales with the number of rows. That is why the gap between the two call paths grows with batch size.

## Base transaction limit

Base currently caps ordinary transactions at 16,777,216 gas (`2^24`).

| Call | Largest measured batch below the cap | Gas | Next batch | Gas |
| --- | ---: | ---: | ---: | ---: |
| `claim` | 438 | 16,740,266 | 439 | 16,779,927 |
| `claimWithSignature` | 406 | 16,745,138 | 407 | 16,788,261 |

A 450-row batch is over the limit for both paths. The load tester now caps its submitted claim gas limit at `2^24`, so an oversized batch fails at the same boundary rather than requesting a transaction gas limit that Base will reject during validation.

For production use:

- **100 rows:** recommended default
- **250 rows:** reasonable large-batch test
- **350 rows:** useful near-limit stress test
- **400 rows:** valid in this build, but tight for `claimWithSignature`
- **438/406 rows:** measurement boundaries only

## Gas cost by action

Deposit, refund, and settlement measurements used a Base mainnet fork at block `48,939,200`, a freshly deployed canonical settlement contract, Base USDC, and the production Permit2 contract.

| Action | Total gas | Notes |
| --- | ---: | --- |
| ERC-3009 deposit | 166,592 | First deposit on a new channel, real Base USDC authorization |
| Permit2 deposit | 154,844 | First deposit on a new channel, real Permit2 witness transfer and Base USDC |
| `claim[1]` | 60,441 | Direct receiver-side claim |
| `claimWithSignature[1]` | 72,384 | Relay-friendly claim with receiver-authorizer batch signature |
| `refund` | 63,314 | Direct receiver-side full refund using Base USDC |
| `settle` | 53,340 | One claimed balance transferred as Base USDC |

These are first-use or state-changing paths. Repeating an operation against already-warm state can be cheaper, while a no-op `settle` with nothing pending is not representative and was not included.

## Calldata

The exact encoded calldata lengths are:

```text
claim:              68 + 480 × rows bytes
claimWithSignature: 228 + 480 × rows bytes
```

Examples:

| Rows | `claim` calldata | `claimWithSignature` calldata |
| ---: | ---: | ---: |
| 1 | 548 bytes | 708 bytes |
| 10 | 4,868 bytes | 5,028 bytes |
| 50 | 24,068 bytes | 24,228 bytes |
| 100 | 48,068 bytes | 48,228 bytes |
| 250 | 120,068 bytes | 120,228 bytes |
| 400 | 192,068 bytes | 192,228 bytes |

The 160-byte difference is the outer dynamic signature argument. Both calls otherwise carry the same 480 bytes per row.

Raw calldata is a useful upper-bound proxy for data availability load, but it is not the same as bytes posted to L1. OP Stack batch compression should compress repeated addresses, zero padding, and similar channel fields. A production DA result should therefore include batcher output, not only transaction input size.

## What the result means for throughput

At roughly 38–41k gas per first-claim row, a 400M-gas block has an execution-only ceiling near 10,000 claim rows per block, or about 5,000 rows per second at two-second blocks.

That is not yet a full-stack x402 TPS number. A `VoucherClaim` row is the latest cumulative state for one channel. It can replace many earlier off-chain payment vouchers. If each on-chain row aggregates `A` payments, then:

```text
represented payment rate ≈ on-chain claim-row rate × A
```

For example, one million represented payments per second would require roughly 200 payments aggregated into each row at a 5,000-row-per-second settlement rate. That aggregation factor must be measured and stated; it cannot be inferred from the contract benchmark.

The final system limit is the minimum of:

- off-chain voucher creation and validation;
- facilitator `/verify` capacity;
- transaction construction and submission;
- sequencer execution;
- state-root processing;
- compressed DA throughput.

## Why one-third of a block is not the limit

Base's current full-block budget is about 400M gas, so one third is roughly 133M gas. The per-transaction cap is only 16.8M gas.

An ordinary transaction therefore cannot consume one third of a Base block. It reaches the transaction cap first, at about 4.2% of the block. For batch settlement, the relevant inclusion boundary is the per-transaction cap measured above.

## Recommended benchmark plan

1. Use 100 rows as the standard reference workload.
2. Sweep 1, 10, 50, 100, 150, 200, 250, 300, 350, and 400 rows.
3. Include 438/439 for the direct-claim boundary and 406/407 for the signed-claim boundary.
4. Report transaction TPS, rows per second, gas per row, calldata per row, and inclusion latency.
5. Measure compressed batcher output before publishing a DA ceiling.
6. Run facilitator `/verify` separately for conservative and optimistic server behavior.
7. State the observed off-chain-payments-per-row aggregation factor before converting settlement rows into payment TPS.

## Sources

- x402 source: `contracts/evm/src/x402BatchSettlement.sol`
- x402 build settings: `contracts/evm/foundry.toml`
- Base, [Throughput and Limits](https://docs.base.org/base-chain/network-information/throughput-and-limits)
- Base, [Transaction Ordering](https://docs.base.org/base-chain/network-information/block-building)
- Base Azul, [Execution Engine Changes](https://docs.base.org/base-chain/specs/upgrades/azul/exec-engine)
