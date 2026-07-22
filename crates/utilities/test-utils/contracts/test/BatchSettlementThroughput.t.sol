// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

/// @notice Locks the block-packing arithmetic used by the batch-settlement report.
/// @dev Gas inputs come from the exhaustive canonical x402 Foundry sweep documented in REPORT.md.
contract BatchSettlementThroughputTest is Test {
    uint256 internal constant FULL_BLOCK_GAS = 400_000_000;
    uint256 internal constant THIRTY_PERCENT_BLOCK_GAS = 120_000_000;
    uint256 internal constant TRANSACTION_GAS_LIMIT = 16_777_216;

    function test_direct_claim_maximum_measured_throughput() public pure {
        uint256 fullBlockGas = 2_185_421;
        uint256 thirtyPercentGas = 2_066_635;

        assertEq(_transactionsPerBlock(FULL_BLOCK_GAS, fullBlockGas), 183);
        assertEq(_rowsPerBlock(FULL_BLOCK_GAS, fullBlockGas, 55), 10_065);

        assertEq(_transactionsPerBlock(THIRTY_PERCENT_BLOCK_GAS, thirtyPercentGas), 58);
        assertEq(_rowsPerBlock(THIRTY_PERCENT_BLOCK_GAS, thirtyPercentGas, 52), 3_016);
    }

    function test_signed_claim_maximum_measured_throughput() public pure {
        uint256 fullBlockGas = 3_052_518;
        uint256 thirtyPercentGas = 2_925_709;

        assertEq(_transactionsPerBlock(FULL_BLOCK_GAS, fullBlockGas), 131);
        assertEq(_rowsPerBlock(FULL_BLOCK_GAS, fullBlockGas, 72), 9_432);

        assertEq(_transactionsPerBlock(THIRTY_PERCENT_BLOCK_GAS, thirtyPercentGas), 41);
        assertEq(_rowsPerBlock(THIRTY_PERCENT_BLOCK_GAS, thirtyPercentGas, 69), 2_829);
    }

    function test_measured_transaction_cap_boundaries() public pure {
        assertLe(16_744_412, TRANSACTION_GAS_LIMIT);
        assertGt(16_785_859, TRANSACTION_GAS_LIMIT);
        assertLe(16_741_757, TRANSACTION_GAS_LIMIT);
        assertGt(16_788_849, TRANSACTION_GAS_LIMIT);
    }

    function _transactionsPerBlock(uint256 blockGas, uint256 transactionGas) internal pure returns (uint256) {
        return blockGas / transactionGas;
    }

    function _rowsPerBlock(uint256 blockGas, uint256 transactionGas, uint256 batchSize)
        internal
        pure
        returns (uint256)
    {
        return _transactionsPerBlock(blockGas, transactionGas) * batchSize;
    }
}
