// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {ISubsidy, Subsidy} from "../../../aztec/Subsidy.sol";

contract SubsidyTest is Test {
    address private constant BRIDGE = address(10);
    address private constant BENEFICIARY = address(11);

    ISubsidy private subsidy;

    function setUp() public {
        subsidy = new Subsidy();

        vm.label(BRIDGE, "BRIDGE");
        vm.label(BENEFICIARY, "TEST_EOA");

        // Make sure test addresses don't hold any ETH
        vm.deal(BRIDGE, 0);
        vm.deal(BENEFICIARY, 0);
    }

    function testArrayLengthsDontMatchError() public {
        // First set min gas per second values for different criteria
        uint256[] memory criteria = new uint256[](1);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerSecond = new uint32[](2);

        vm.expectRevert(Subsidy.ArrayLengthsDoNotMatch.selector);
        subsidy.setGasUsageAndMinGasPerSecond(criteria, gasUsage, minGasPerSecond);
    }

    function testGasPerSecondTooLowError() public {
        // 1st set min gas per second values for different criteria
        _setGasUsageAndMinGasPerSecond();

        vm.expectRevert(Subsidy.GasPerSecondTooLow.selector);
        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 4);
    }

    function testAlreadySubsidizedError() public {
        // 1st set min gas per second values for different criteria
        _setGasUsageAndMinGasPerSecond();

        // 2nd subsidize criteria 3
        subsidy.subsidize{value: 1 ether}(BRIDGE, 3, 45);

        // 3rd try to set subsidy again
        vm.expectRevert(Subsidy.AlreadySubsidized.selector);
        subsidy.subsidize{value: 2 ether}(BRIDGE, 3, 50);
    }

    function testGasUsageNotSetError() public {
        vm.expectRevert(Subsidy.GasUsageNotSet.selector);
        subsidy.subsidize{value: 1 ether}(BRIDGE, 3, 55);
    }

    function testSubsidyTooLowError() public {
        // 1st set min gas per second values for different criteria
        _setGasUsageAndMinGasPerSecond();

        // 2nd check the call reverts with SubsidyTooLow error
        vm.expectRevert(Subsidy.SubsidyTooLow.selector);
        subsidy.subsidize{value: 1e17 - 1}(BRIDGE, 3, 55);
    }

    function testSubsidyGetsCorrectlySet() public {
        _setGasUsageAndMinGasPerSecond();

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 10);

        (uint128 available, uint32 gasUsage, uint32 minGasPerSecond, uint32 gasPerSecond, uint32 lastUpdated) = subsidy
            .subsidies(BRIDGE, 1);

        assertEq(available, 1 ether, "available incorrectly set");
        assertEq(gasUsage, 5e4, "gasUsage incorrectly set");
        assertEq(minGasPerSecond, 5, "minGasPerSecond incorrectly set");
        assertEq(gasPerSecond, 10, "gasPerSecond incorrectly set");
        assertEq(lastUpdated, block.timestamp, "lastUpdated incorrectly set");
    }

    function testClaimRevertsIfBeneficiaryIsContractAndDoesntImplementReceive() public {
        // 1st set min gas per second values for different criterias
        _setGasUsageAndMinGasPerSecond();

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 10);

        vm.warp(block.timestamp + 1 days);

        // This should revert because address(this) is a contract and doesn't implement receive/fallback functions
        vm.prank(BRIDGE);
        vm.expectRevert(Subsidy.EthTransferFailed.selector);
        subsidy.claimSubsidy(1, address(this));
    }

    function testAllSubsidyGetsClaimedAndSubsidyCanBeRefilledAfterThat() public {
        // Set huge gasUsage so that everything can be claimed in 1 call
        uint32 gasUsage = type(uint32).max;
        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerSecond(1, gasUsage, 10);

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 1000);
        (uint128 available, , , , uint32 lastUpdated) = subsidy.subsidies(BRIDGE, 1);
        assertEq(available, 1 ether, "available incorrectly set");
        assertEq(lastUpdated, block.timestamp, "lastUpdated incorrectly set");

        vm.warp(block.timestamp + 7 days);

        vm.prank(BRIDGE);
        subsidy.claimSubsidy(1, BENEFICIARY);

        (available, , , , lastUpdated) = subsidy.subsidies(BRIDGE, 1);

        assertEq(BENEFICIARY.balance, 1 ether, "beneficiary didn't receive full subsidy");
        assertEq(available, 0, "not all subsidy was claimed");
        assertEq(lastUpdated, block.timestamp, "lastUpdated incorrectly updated");

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 1000);
        (available, , , , ) = subsidy.subsidies(BRIDGE, 1);

        assertEq(available, 1 ether, "available incorrectly set in refill");
    }

    function testAvailableDropsByExpectedAmount() public {
        _setGasUsageAndMinGasPerSecond();

        uint256 dt = 3600;
        uint32 gasPerSecond = 10;

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, gasPerSecond);
        (uint128 available, , , , uint32 lastUpdated) = subsidy.subsidies(BRIDGE, 1);
        assertEq(available, 1 ether, "available incorrectly set");

        uint256 expectedSubsidyAmount = dt * gasPerSecond * block.basefee;

        vm.warp(block.timestamp + dt);

        vm.prank(BRIDGE);
        uint256 subsidyAmount = subsidy.claimSubsidy(1, BENEFICIARY);

        assertEq(subsidyAmount, expectedSubsidyAmount);
        assertEq(subsidyAmount, BENEFICIARY.balance, "subsidyAmount differs from beneficiary's balance");

        (available, , , , ) = subsidy.subsidies(BRIDGE, 1);

        assertEq(available, 1 ether - subsidyAmount, "unexpected value of available");
    }

    function _setGasUsageAndMinGasPerSecond() private {
        uint256[] memory criterias = new uint256[](4);
        uint32[] memory gasUsage = new uint32[](4);
        uint32[] memory minGasPerSecond = new uint32[](4);

        criterias[0] = 1;
        criterias[1] = 2;
        criterias[2] = 3;
        criterias[3] = 4;

        gasUsage[0] = 5e4;
        gasUsage[1] = 10e4;
        gasUsage[2] = 15e4;
        gasUsage[3] = 20e4;

        minGasPerSecond[0] = 5;
        minGasPerSecond[1] = 10;
        minGasPerSecond[2] = 15;
        minGasPerSecond[3] = 20;

        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerSecond(criterias, gasUsage, minGasPerSecond);
    }
}
