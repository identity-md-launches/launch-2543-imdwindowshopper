// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";
import {TokenTestBase, TokenVm} from "./helpers/TokenTestBase.sol";

/// @dev Test-only factory: demonstrates that a contract deployer receives the entire supply.
contract TokenFactoryHarness {
    function deploy() external returns (IMDwindowshopper) {
        return new IMDwindowshopper();
    }

    function distribute(IMDwindowshopper token, address recipient, uint256 amount)
        external
        returns (bool)
    {
        return token.transfer(recipient, amount);
    }
}

contract IMDwindowshopperTest is TokenTestBase {
    IMDwindowshopper internal token;

    // Independent expected value: a wrong production constant must fail these tests.
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        token = new IMDwindowshopper();
    }

    function test_MetadataAndSupplyMatchRequest() public view {
        assertEq(token.name(), "IMDwindowshopper", "wrong name");
        assertEq(token.symbol(), "WWW", "wrong symbol");
        assertEq(token.decimals(), 18, "wrong decimals");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "wrong initial supply constant");
        assertEq(token.totalSupply(), SUPPLY, "wrong total supply");
    }

    function test_EntireSupplyBelongsToDeployer() public view {
        assertEq(token.balanceOf(address(this)), SUPPLY, "deployer did not receive full supply");
        assertEq(token.balanceOf(address(token)), 0, "token retained an allocation");
        assertEq(token.balanceOf(ALICE), 0, "unexpected allocation");
        assertEq(token.balanceOf(address(0)), 0, "unexpected zero-address balance");
        assertEq(token.allowance(address(this), SPENDER), 0, "unexpected initial approval");
    }

    function test_ConstructorEmitsOneMintTransfer() public {
        vm.recordLogs();
        IMDwindowshopper fresh = new IMDwindowshopper();
        TokenVm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1, "constructor must emit exactly one mint");
        assertEq(logs[0].emitter, address(fresh), "wrong event emitter");
        assertEq(logs[0].topics.length, 3, "wrong mint event topics");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"), "wrong event");
        assertEq(logs[0].topics[1], bytes32(0), "mint did not originate at zero");
        assertEq(
            logs[0].topics[2], bytes32(uint256(uint160(address(this)))), "wrong mint recipient"
        );
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "wrong mint event amount");
    }

    function test_FactoryReceivesSupplyAndCanDistributeItExactly() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        IMDwindowshopper fresh = factory.deploy();

        assertEq(fresh.balanceOf(address(factory)), SUPPLY, "factory did not receive full supply");
        assertEq(fresh.balanceOf(address(this)), 0, "factory caller received supply");

        uint256 swarmShare = SUPPLY / 10;
        assertTrue(factory.distribute(fresh, ALICE, swarmShare), "factory distribution failed");
        assertEq(fresh.balanceOf(ALICE), swarmShare, "distribution arrived short");
        vm.prank(ALICE);
        assertTrue(fresh.transfer(BOB, swarmShare), "claim transfer failed");
        assertEq(fresh.balanceOf(BOB), swarmShare, "claim arrived short");
        assertEq(fresh.balanceOf(ALICE), 0, "distributor retained tokens");
        assertEq(fresh.balanceOf(address(factory)), SUPPLY - swarmShare, "wrong factory remainder");
        assertEq(fresh.totalSupply(), SUPPLY, "distribution changed supply");
    }

    function test_TransferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 25 ether);
        assertTrue(token.transfer(ALICE, 25 ether), "transfer did not return true");

        assertEq(token.balanceOf(ALICE), 25 ether, "recipient received wrong amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether, "wrong sender balance");
        assertEq(token.totalSupply(), SUPPLY, "transfer changed supply");
    }

    function test_TransferEntireBalance() public {
        assertTrue(token.transfer(ALICE, SUPPLY), "full balance transfer failed");
        assertEq(token.balanceOf(address(this)), 0, "sender retained tokens");
        assertEq(token.balanceOf(ALICE), SUPPLY, "recipient did not receive full balance");
        assertEq(token.totalSupply(), SUPPLY, "transfer changed supply");
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "zero transfer failed");
        assertEq(token.balanceOf(ALICE), 0, "empty sender gained tokens");
        assertEq(token.balanceOf(BOB), 0, "zero transfer created tokens");
        assertEq(token.totalSupply(), SUPPLY, "zero transfer changed supply");
    }

    function test_TransferToZeroAddressReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed transfer changed balance");
        assertEq(token.totalSupply(), SUPPLY, "failed transfer changed supply");
    }

    function test_ZeroTransferToZeroAddressAlsoReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
    }

    function test_TransferFromEmptyAccountReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0, "failed transfer credited recipient");
        assertEq(token.totalSupply(), SUPPLY, "failed transfer changed supply");
    }

    function test_SelfTransferAboveBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed self-transfer changed balance");
    }

    function test_ApproveEmitsEventWithoutMovingTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 50 ether), "approve did not return true");
        assertEq(token.allowance(address(this), SPENDER), 50 ether, "wrong allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY, "approval moved tokens");
        assertEq(token.balanceOf(SPENDER), 0, "approval credited spender");
        assertEq(token.totalSupply(), SUPPLY, "approval changed supply");
    }

    function test_ApproveOverwritesAndCanBeRevoked() public {
        token.approve(SPENDER, 50 ether);
        token.approve(SPENDER, 7 ether);
        assertEq(token.allowance(address(this), SPENDER), 7 ether, "approval was not overwritten");
        token.approve(SPENDER, 0);
        assertEq(token.allowance(address(this), SPENDER), 0, "approval was not revoked");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY, "revoked spender moved tokens");
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0, "invalid approval persisted");
    }

    function test_TransferFromSpendsAllowanceAndEmitsTransfer() public {
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 60 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 40 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 40 ether), "delegated transfer failed");
        assertEq(token.balanceOf(ALICE), 60 ether, "wrong holder balance");
        assertEq(token.balanceOf(BOB), 40 ether, "delegated transfer arrived short");
        assertEq(token.balanceOf(SPENDER), 0, "spender kept tokens");
        assertEq(token.allowance(ALICE, SPENDER), 20 ether, "allowance not consumed");
        assertEq(token.totalSupply(), SUPPLY, "delegated transfer changed supply");
    }

    function test_TransferFromCanSpendEntireAllowanceAndBalance() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY), "full delegated transfer failed");
        assertEq(token.balanceOf(address(this)), 0, "holder retained balance");
        assertEq(token.balanceOf(BOB), SUPPLY, "recipient received wrong balance");
        assertEq(token.allowance(address(this), SPENDER), 0, "allowance not exhausted");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
    }

    function test_MaximumAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 5 ether), "unlimited approval failed");
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max, "max approval changed");
        assertEq(token.balanceOf(BOB), 5 ether, "wrong recipient amount");
        assertEq(token.totalSupply(), SUPPLY, "delegated transfer changed supply");
    }

    function test_ApprovalForAnotherSpenderDoesNotAuthorizeCaller() public {
        token.approve(SPENDER, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1)
        );
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY, "unapproved caller moved tokens");
        assertEq(token.allowance(address(this), SPENDER), 100 ether, "another approval changed");
    }

    function test_DeployerCannotSpendHolderTokensWithoutApproval() public {
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 10 ether, "deployer seized holder tokens");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether), "holder could not transfer afterwards");
    }

    function test_TransferFromRequiresAllowanceEvenWhenCallerIsHolder() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(address(this), BOB, 1);
    }

    function test_FailedTransferFromRollsBackAllowanceOnInsufficientBalance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 20 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10 ether);
        assertEq(token.allowance(ALICE, SPENDER), 20 ether, "failed transfer consumed allowance");
        assertEq(token.balanceOf(BOB), 0, "failed transfer credited recipient");
        assertEq(token.totalSupply(), SUPPLY, "failed transfer changed supply");
    }

    function test_FailedTransferFromRollsBackAllowanceOnZeroRecipient() public {
        token.approve(SPENDER, 20 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(
            token.allowance(address(this), SPENDER), 20 ether, "failed transfer consumed allowance"
        );
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed transfer moved tokens");
    }

    function test_ZeroTransferFromWithoutAllowanceIsAllowed() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0), "zero delegated transfer failed");
        assertEq(token.allowance(ALICE, SPENDER), 0, "zero transfer changed allowance");
        assertEq(token.balanceOf(ALICE), 0, "zero transfer changed holder balance");
        assertEq(token.balanceOf(BOB), 0, "zero transfer changed recipient balance");
        assertEq(token.totalSupply(), SUPPLY, "zero delegated transfer changed supply");
    }

    function test_TransferFromZeroSenderRevertsEvenForZeroAmount() public {
        // The allowance update validates its owner before the transfer validates its sender.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
        );
        token.transferFrom(address(0), BOB, 0);
    }

    function test_DelegatedSelfTransferConsumesAllowanceWithoutChangingBalance() public {
        token.approve(SPENDER, 20 ether);
        vm.prank(SPENDER);
        assertTrue(
            token.transferFrom(address(this), address(this), 10 ether), "self-transfer failed"
        );
        assertEq(token.balanceOf(address(this)), SUPPLY, "self-transfer changed balance");
        assertEq(token.allowance(address(this), SPENDER), 10 ether, "wrong remaining allowance");
        assertEq(token.totalSupply(), SUPPLY, "self-transfer changed supply");
    }

    function test_MintBurnInitializationAndUpgradeEntrypointsAreUnavailable() public {
        bytes[8] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1 ether),
            abi.encodeWithSignature("mint(uint256)", 1 ether),
            abi.encodeWithSignature("burn(uint256)", 1 ether),
            abi.encodeWithSignature("burnFrom(address,uint256)", address(this), 1 ether),
            abi.encodeWithSignature("initialize()"),
            abi.encodeWithSignature("initialize(address)", ALICE),
            abi.encodeWithSignature("setMinter(address)", ALICE),
            abi.encodeWithSignature("upgradeTo(address)", ALICE)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertTrue(!deployerSucceeded, "deployer reached an unsupported entrypoint");
            vm.prank(ALICE);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertTrue(!strangerSucceeded, "stranger reached an unsupported entrypoint");
        }
        assertEq(token.totalSupply(), SUPPLY, "unsupported calls changed supply");
        assertEq(token.balanceOf(address(this)), SUPPLY, "unsupported calls moved supply");
        assertEq(token.balanceOf(ALICE), 0, "unsupported calls minted tokens");
    }

    function test_DeployerCannotFreezeSeizeOrAdministerHolders() public {
        token.transfer(ALICE, 10 ether);
        bytes[7] memory calls = [
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("freeze(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("setTransfersEnabled(bool)", false),
            abi.encodeWithSignature("transferOwnership(address)", ALICE),
            abi.encodeWithSignature("owner()")
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool succeeded,) = address(token).call(calls[i]);
            assertTrue(!succeeded, "unexpected administrative entrypoint");
        }
        assertEq(token.balanceOf(ALICE), 10 ether, "administrative call moved holder balance");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether), "holder was frozen");
        assertEq(token.balanceOf(BOB), 10 ether, "holder transfer arrived short");
        assertEq(token.totalSupply(), SUPPLY, "administrative call changed supply");
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        if (recipient == address(0) || recipient == address(this)) recipient = ALICE;
        uint256 amount = rawAmount % (SUPPLY + 1);

        assertTrue(token.transfer(recipient, amount), "fuzz transfer failed");
        assertEq(token.balanceOf(recipient), amount, "fuzz recipient received wrong amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "fuzz sender balance is wrong");
        assertEq(token.totalSupply(), SUPPLY, "fuzz transfer changed supply");
    }

    function testFuzz_SelfTransferCannotInflateBalance(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(address(this), amount), "fuzz self-transfer failed");
        assertEq(token.balanceOf(address(this)), SUPPLY, "self-transfer inflated balance");
        assertEq(token.totalSupply(), SUPPLY, "self-transfer changed supply");
    }

    function testFuzz_TransferAboveBalanceReverts(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = rawBalance % (SUPPLY + 1);
        uint256 amount = balance + 1 + (rawExcess % (type(uint256).max - balance));
        token.transfer(ALICE, balance);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount
            )
        );
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), balance, "failed fuzz transfer changed sender balance");
        assertEq(token.balanceOf(BOB), 0, "failed fuzz transfer credited recipient");
        assertEq(token.totalSupply(), SUPPLY, "failed fuzz transfer changed supply");
    }

    function testFuzz_TransferFromConsumesFiniteAllowance(uint256 rawAllowance, uint256 rawAmount)
        public
    {
        uint256 approved = rawAllowance % (SUPPLY + 1);
        uint256 amount = rawAmount % (approved + 1);
        token.approve(SPENDER, approved);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, amount), "fuzz delegated transfer failed");
        assertEq(token.allowance(address(this), SPENDER), approved - amount, "wrong fuzz allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "wrong fuzz holder balance");
        assertEq(token.balanceOf(BOB), amount, "wrong fuzz recipient balance");
        assertEq(token.totalSupply(), SUPPLY, "fuzz delegated transfer changed supply");
    }

    function testFuzz_TransferFromAboveAllowanceReverts(uint256 rawAllowance, uint256 rawExtra)
        public
    {
        uint256 approved = rawAllowance % SUPPLY;
        uint256 amount = approved + 1 + (rawExtra % (SUPPLY - approved));
        token.approve(SPENDER, approved);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, amount);
        assertEq(token.allowance(address(this), SPENDER), approved, "failed call changed allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed call moved holder tokens");
        assertEq(token.balanceOf(BOB), 0, "failed call credited recipient");
        assertEq(token.totalSupply(), SUPPLY, "failed fuzz transfer changed supply");
    }

    function testFuzz_TransferSequenceConservesAllBalances(bytes32 entropy) public {
        address[4] memory actors = [address(this), ALICE, BOB, SPENDER];
        for (uint256 i; i < 32; ++i) {
            uint256 choice = uint256(keccak256(abi.encode(entropy, i)));
            address from = actors[choice % actors.length];
            address to = actors[(choice >> 8) % actors.length];
            uint256 amount = (choice >> 16) % (token.balanceOf(from) + 1);

            vm.prank(from);
            assertTrue(token.transfer(to, amount), "sequence transfer failed");
            uint256 balances;
            for (uint256 j; j < actors.length; ++j) {
                balances += token.balanceOf(actors[j]);
            }
            assertEq(balances, SUPPLY, "sequence created or destroyed tokens");
            assertEq(token.totalSupply(), SUPPLY, "sequence changed total supply");
        }
    }
}
