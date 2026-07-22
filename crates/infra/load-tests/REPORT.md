# x402 Batch Settlement: Gas and Batch-Size Report

Date: July 22, 2026

## Summary

The maximum execution-only settlement rates measured were:

| Block allocation | Direct `claim` | `claimWithSignature` |
| --- | ---: | ---: |
| 100% of a 400M-gas block | **5,032.5 voucher rows/s** at 55 rows/tx | **4,716 voucher rows/s** at 72 rows/tx |
| 30% of a 400M-gas block | **1,508 voucher rows/s** at 52 rows/tx | **1,414.5 voucher rows/s** at 69 rows/tx |

These are settled voucher rows per second, not off-chain payment TPS. One cumulative voucher row can represent many payments, but that aggregation factor is application-dependent.

The practical default remains **100 rows per transaction**. It delivers 5,000 direct rows/s or 4,700 signed rows/s when packed into full blocks—within 0.7% of the measured maxima—while using fewer, larger transactions.

The largest representative batches measured below Base's 16,777,216 transaction gas limit were 409 rows for `claim` and 382 rows for `claimWithSignature`. Those are transaction-size boundaries, not throughput optima.

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

The throughput search measured every integer batch size from 1 through 438 in an isolated Foundry test. For each size, it calculated whole transactions that fit into either a 400M-gas block or a 120M-gas (30%) allocation. Channel fields, salts, and signatures used representative non-zero values so calldata gas was not understated by zero-heavy fixtures.

## Claim batch-size results

| Rows | `claim` gas | Gas/row | `claimWithSignature` gas | Gas/row |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 62,044 | 62,044 | 74,165 | 74,165 |
| 10 | 414,170 | 41,417 | 448,537 | 44,854 |
| 50 | 1,987,586 | 39,752 | 2,123,426 | 42,469 |
| 100 | 3,974,095 | 39,741 | 4,242,951 | 42,430 |
| 150 | 5,982,876 | 39,886 | 6,391,661 | 42,611 |
| 200 | 8,014,197 | 40,071 | 8,569,763 | 42,849 |
| 250 | 10,067,573 | 40,270 | 10,776,854 | 43,107 |
| 300 | 12,142,816 | 40,476 | 13,012,564 | 43,375 |
| 350 | 14,240,034 | 40,686 | 15,277,173 | 43,649 |
| 400 | 16,359,341 | 40,898 | 17,570,773 | 43,927 |

The first 50 rows provide most of the amortization. Gas per row is broadly flat around 50–100 rows, then rises gradually as the dynamic arrays and EIP-712 batch hashing grow. Whole-transaction packing—not a large change in per-row cost—selects 55 direct rows and 72 signed rows as the full-block optima. The difference from 100 rows is small enough that 100 remains a practical default.

`claimWithSignature` has two extra costs:

1. it hashes every row into the receiver-authorizer batch digest;
2. it verifies the receiver-authorizer signature.

The second cost is fixed, but the first scales with the number of rows. That is why the gap between the two call paths grows with batch size.

## Base transaction limit

Base currently caps ordinary transactions at 16,777,216 gas (`2^24`).

| Call | Largest measured batch below the cap | Gas | Next batch | Gas |
| --- | ---: | ---: | ---: | ---: |
| `claim` | 409 | 16,744,412 | 410 | 16,785,859 |
| `claimWithSignature` | 382 | 16,741,757 | 383 | 16,788,849 |

The load tester caps its submitted claim gas limit at `2^24`, so an oversized batch fails at the same boundary rather than requesting a transaction gas limit that Base will reject during validation.

For production use:

- **100 rows:** recommended default
- **55 direct / 72 signed rows:** maximum measured full-block packing
- **52 direct / 69 signed rows:** maximum measured packing at a 30% block allocation
- **350 rows:** useful near-limit stress test
- **409/382 rows:** transaction-cap boundaries only

## Gas cost by action

Deposit, refund, and settlement measurements used a Base mainnet fork at block `48,939,200`, a freshly deployed canonical settlement contract, Base USDC, and the production Permit2 contract.

| Action | Total gas | Notes |
| --- | ---: | --- |
| ERC-3009 deposit | 166,592 | First deposit on a new channel, real Base USDC authorization |
| Permit2 deposit | 154,844 | First deposit on a new channel, real Permit2 witness transfer and Base USDC |
| `claim[1]` | 62,044 | Direct receiver-side claim |
| `claimWithSignature[1]` | 74,165 | Relay-friendly claim with receiver-authorizer batch signature |
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

At roughly 40–44k gas per first-claim row, a 400M-gas block has an execution-only ceiling near 10,000 claim rows per block, or about 5,000 rows per second at two-second blocks.

That is not yet a full-stack x402 TPS number. A `VoucherClaim` row is the latest cumulative state for one channel. It can replace many earlier off-chain payment vouchers. If each on-chain row aggregates `A` payments, then:

```text
represented payment rate ≈ on-chain claim-row rate × A
```

For example, one million represented payments per second would require about 199 payments per direct-claim row or 212 payments per signed-claim row at the full-block rates measured here. That aggregation factor must be measured and stated; it cannot be inferred from the contract benchmark.

### Execution-only throughput by batch size

The following ceilings apply the measured gas costs to a 400M-gas block produced every two seconds. They assume execution is the only constraint; they are not observed end-to-end rates and do not account for DA, state-root processing, or transaction-submission limits.

| Rows | `claim` tx/s | `claim` rows/s | `claim` calldata/row | `claimWithSignature` tx/s | `claimWithSignature` rows/s | Signed calldata/row |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 3,223.52 | 3,224 | 548.0 bytes | 2,696.69 | 2,697 | 708.0 bytes |
| 10 | 482.89 | 4,829 | 486.8 bytes | 445.89 | 4,459 | 502.8 bytes |
| 50 | 100.62 | 5,031 | 481.4 bytes | 94.19 | 4,709 | 484.6 bytes |
| 100 | 50.33 | 5,033 | 480.7 bytes | 47.14 | 4,714 | 482.3 bytes |
| 150 | 33.43 | 5,014 | 480.5 bytes | 31.29 | 4,694 | 481.5 bytes |
| 200 | 24.96 | 4,991 | 480.3 bytes | 23.34 | 4,668 | 481.1 bytes |
| 250 | 19.87 | 4,966 | 480.3 bytes | 18.56 | 4,640 | 480.9 bytes |
| 300 | 16.47 | 4,941 | 480.2 bytes | 15.37 | 4,611 | 480.8 bytes |
| 350 | 14.04 | 4,916 | 480.2 bytes | 13.09 | 4,582 | 480.7 bytes |
| 400 | 12.23 | 4,890 | 480.2 bytes | — | — | 480.6 bytes |

Those rates divide a continuous 200M gas/s budget by one transaction's measured gas. Real blocks contain whole transactions, so the exhaustive packing search gives the more precise maxima:

| Call | Allocation | Rows/tx | Gas/tx | Tx/block | Rows/block | Rows/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `claim` | 100% | 55 | 2,185,421 | 183 | 10,065 | **5,032.5** |
| `claim` | 30% | 52 | 2,066,635 | 58 | 3,016 | **1,508** |
| `claimWithSignature` | 100% | 72 | 3,052,518 | 131 | 9,432 | **4,716** |
| `claimWithSignature` | 30% | 69 | 2,925,709 | 41 | 2,829 | **1,414.5** |

The selected configurations use 99.9% or more of their assigned gas budgets. A 100-row default packs 10,000 direct rows or 9,400 signed rows into a full block, so tuning batch size improves maximum throughput by only 0.65% and 0.34%, respectively.

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
