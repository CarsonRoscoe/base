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

### Execution-only throughput by batch size

The following ceilings apply the measured gas costs to a 400M-gas block produced every two seconds. They assume execution is the only constraint; they are not observed end-to-end rates and do not account for DA, state-root processing, or transaction-submission limits.

| Rows | `claim` tx/s | `claim` rows/s | `claim` calldata/row | `claimWithSignature` tx/s | `claimWithSignature` rows/s | Signed calldata/row |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 3,309.01 | 3,309 | 548.0 bytes | 2,763.04 | 2,763 | 708.0 bytes |
| 10 | 497.07 | 4,971 | 486.8 bytes | 458.20 | 4,582 | 502.8 bytes |
| 50 | 104.02 | 5,201 | 481.4 bytes | 97.17 | 4,858 | 484.6 bytes |
| 100 | 52.29 | 5,229 | 480.7 bytes | 48.86 | 4,886 | 482.3 bytes |
| 150 | 34.91 | 5,236 | 480.5 bytes | 32.59 | 4,888 | 481.5 bytes |
| 200 | 26.19 | 5,238 | 480.3 bytes | 24.42 | 4,884 | 481.1 bytes |
| 250 | 20.95 | 5,239 | 480.3 bytes | 19.51 | 4,877 | 480.9 bytes |
| 300 | 17.46 | 5,238 | 480.2 bytes | 16.23 | 4,868 | 480.8 bytes |
| 350 | 14.96 | 5,236 | 480.2 bytes | 13.88 | 4,859 | 480.7 bytes |
| 400 | 13.09 | 5,234 | 480.2 bytes | 12.13 | 4,850 | 480.6 bytes |

The table confirms that 100 rows captures almost all available execution efficiency. Moving from 100 to 250 direct claims improves the execution ceiling by only 0.2%; for signed claims, 100 rows is already slightly more efficient than 250.

The final system limit is the minimum of:

- off-chain voucher creation and validation;
- facilitator `/verify` capacity;
- transaction construction and submission;
- sequencer execution;
- state-root processing;
- compressed DA throughput.

## Mixed-workload devnet result

The checked-in devnet workload was rerun with 10 senders, eight rows per signed claim, a 20M gas/s target, and the 90/5/4/1 transaction mix. The 30-second generation window produced 1,780 transactions:

| Action | Transactions | Claim rows |
| --- | ---: | ---: |
| `claimWithSignature` | 1,595 | 12,760 |
| ERC-3009 deposit | 101 | — |
| `settle` | 71 | — |
| `refund` | 13 | — |

All 1,780 transactions confirmed, with no submission failures or reverts. The observed aggregate rate was 37.08 tx/s and 9.04M gas/s. Applying the exact claim share to that observed rate gives 33.23 signed claim transactions/s, or **265.8 confirmed claim rows/s**. The transactions carried 6,558,480 bytes of calldata in total, averaging 3,684.5 bytes per transaction.

| Inclusion metric | Minimum | p50 | Mean | p95 | p99 | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Block | 670.9 ms | 2.9 s | 6.6 s | 28.3 s | 37.5 s | 40.1 s |
| Flashblock | 95.4 ms | 1.0 s | 5.2 s | 26.8 s | 35.4 s | 36.9 s |

This run validates transaction construction, ordering, execution, and receipt accounting. It is not a production capacity result: the recovered HA devnet's follower remained at genesis, so the healthy builder was used for both submission and queries. The high tail latency reflects that local environment and should not be used as a Base mainnet latency estimate.

## Measurements still required for a full-stack TPS claim

The devnet batcher exposed input, compressed-output, and submitted-DA counters, but it detected a chain reorganization during the measurement and reset with 1,275 pending blocks and 317 ready channels. That invalidates a before/after compression delta. No compressed-DA ceiling is reported here; it needs a clean, stable run with counter snapshots bracketing only the measured workload.

Facilitator `/verify` was not exercised by this on-chain workload. The conservative path performs signature validation and reads current channel state over RPC. An optimistic server can validate vouchers locally and periodically resynchronize. Those modes need a separate HTTP benchmark with valid voucher payloads, controlled RPC latency, and an explicit resynchronization interval.

The workload also does not model how many off-chain payments are represented by one cumulative voucher row. Until a resource-server test records that aggregation factor, settlement rows/s must not be presented as payment TPS.

## Sources

- x402 source: `contracts/evm/src/x402BatchSettlement.sol`
- x402 build settings: `contracts/evm/foundry.toml`
- Base, [Throughput and Limits](https://docs.base.org/base-chain/network-information/throughput-and-limits)
- Base, [Transaction Ordering](https://docs.base.org/base-chain/network-information/block-building)
- Base Azul, [Execution Engine Changes](https://docs.base.org/base-chain/specs/upgrades/azul/exec-engine)
