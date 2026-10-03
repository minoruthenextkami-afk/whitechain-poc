// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import { console } from "forge-std/Test.sol";
import { IMapper } from "../../ether/contracts/main/modules/mapper/interfaces/IMapper.sol";
import { IBridge } from "../../ether/contracts/main/modules/bridge/interfaces/IBridge.sol";
import { WhitechainBridgeTestBase } from "./WhitechainBridgeTestBase.sol";
import { FalseReturnERC20 } from "./mocks/FalseReturnERC20.sol";

/**
 * @title MediumSeverityFindingsTest
 * @notice Executable verification of the four proposed Medium findings plus the
 *         additional candidates surfaced during review.
 */
contract MediumSeverityFindingsTest is WhitechainBridgeTestBase {
    uint256 public userPrivateKey = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
    address public user;
    bytes32 public constant USER_TO = bytes32(uint256(uint160(0xBEEF)));

    function setUp() public {
        user = vm.addr(userPrivateKey);
        vm.deal(user, 100_000 ether);
        _deployBridge(relayerPrivateKey);
    }

    function _registerCoinDepositMapping() internal {
        vm.prank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: block.chainid,
            targetChainId: 2,
            depositType: IMapper.DepositType.Lock,
            withdrawType: IMapper.WithdrawType.None,
            originTokenAddress: bytes32(uint256(uint160(0xC01E))),
            targetTokenAddress: bytes32(uint256(uint160(0xC0DE))),
            useTransfer: false,
            isAllowed: true,
            isCoin: true
        }));
    }

    function _signBridgeParams(
        uint256 amount,
        uint256 gasAmount,
        bytes32 targetToken,
        uint64 deadline,
        bytes32 salt
    ) internal returns (IBridge.BridgeTokensParams memory) {
        bytes32 h = _computeBridgeHash(
            user, USER_TO, targetToken, gasAmount, amount, block.chainid, 2, deadline, salt
        );
        (uint8 v, bytes32 r, bytes32 s) = _signHash(relayerPrivateKey, h);
        return IBridge.BridgeTokensParams({
            bridgeParams: IBridge.BridgeParams({ mapId: 1, amount: amount, toAddress: USER_TO }),
            ECDSAParams: IBridge.ECDSAParams({ r: r, s: s, salt: salt, deadline: deadline, v: v })
        });
    }

    /* ------------------------------------------------------------------ */
    /* M1 - unchecked ERC-20 transfer return in _executeTokenTransfer       */
    /* ------------------------------------------------------------------ */

    function _setupUseTransferTrueMapping(address token) internal {
        vm.startPrank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 2,
            targetChainId: block.chainid,
            depositType: IMapper.DepositType.None,
            withdrawType: IMapper.WithdrawType.Unlock,
            originTokenAddress: bytes32(uint256(uint160(0xDEAD))),
            targetTokenAddress: bytes32(uint256(uint160(token))),
            useTransfer: true,
            isAllowed: true,
            isCoin: false
        }));
        bridge.setDailyLimit(bytes32(uint256(uint160(token))), relayer, 1_000_000 ether);
        vm.stopPrank();
    }

    function test_M1_silent_loss_when_useTransfer_true_and_token_returns_false() public {
        FalseReturnERC20 token = new FalseReturnERC20();
        _setupUseTransferTrueMapping(address(token));

        // Bridge is funded, but the payout recipient is blacklisted by the token issuer,
        // so transfer() returns false instead of reverting.
        address recipient = address(0xCAFE);
        token.mint(address(bridge), 500_000 ether);
        token.blacklist(recipient);

        uint256 recipientBefore = token.balanceOf(recipient);
        uint256 bridgeBefore = token.balanceOf(address(bridge));

        vm.prank(relayer);
        bridge.receiveTokens(IBridge.ReceiveTokensParams({
            externalId: bytes32(uint256(0xE1)),
            mapId: 1,
            amount: 1_000 ether,
            fromAddress: bytes32(uint256(uint160(user))),
            toAddress: bytes32(uint256(uint160(recipient)))
        }));

        assertEq(token.balanceOf(recipient), recipientBefore, "recipient balance unchanged");
        assertEq(token.balanceOf(address(bridge)), bridgeBefore, "bridge balance unchanged");
        assertEq(bridge.gasAccumulated(), 0, "no gas involved");

        console.log("bridge token balance before :", bridgeBefore);
        console.log("bridge token balance after  :", token.balanceOf(address(bridge)));
        console.log("recipient balance after     :", token.balanceOf(recipient));
        console.log("IMPACT: receiveTokens returned success, Withdrawal emitted, 0 tokens moved");
    }

    function test_M1_control_safeTransfer_path_reverts_instead() public {
        FalseReturnERC20 token = new FalseReturnERC20();
        token.mint(address(bridge), 500_000 ether);
        token.blacklist(address(0xCAFE));

        vm.startPrank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 2,
            targetChainId: block.chainid,
            depositType: IMapper.DepositType.None,
            withdrawType: IMapper.WithdrawType.Unlock,
            originTokenAddress: bytes32(uint256(uint160(0xBEEF))),
            targetTokenAddress: bytes32(uint256(uint160(address(token)))),
            useTransfer: false,
            isAllowed: true,
            isCoin: false
        }));
        bridge.setDailyLimit(bytes32(uint256(uint160(address(token)))), relayer, 1_000_000 ether);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert();
        bridge.receiveTokens(IBridge.ReceiveTokensParams({
            externalId: bytes32(uint256(0xE2)),
            mapId: 1,
            amount: 1_000 ether,
            fromAddress: bytes32(uint256(uint160(user))),
            toAddress: bytes32(uint256(uint160(address(0xCAFE))))
        }));
        console.log("CONTROL: useTransfer=false path reverts (SafeERC20)");
    }

    /* ------------------------------------------------------------------ */
    /* M2 - no upper bound on the signature deadline                        */
    /* ------------------------------------------------------------------ */

    function test_M2_max_uint64_deadline_accepted() public {
        _registerCoinDepositMapping();

        IBridge.BridgeTokensParams memory p =
            _signBridgeParams(1 ether, 0, bytes32(uint256(uint160(0xC0DE))), type(uint64).max, bytes32(uint256(0x5)));

        vm.prank(user);
        bridge.bridgeTokens{ value: 1 ether }(p);

        assertEq(bridge.gasAccumulated(), 0, "deposit credited");
        console.log("accepted deadline = type(uint64).max =", type(uint64).max);
    }

    function test_M2_same_authorization_still_valid_10_years_later() public {
        _registerCoinDepositMapping();

        uint64 far = type(uint64).max;
        IBridge.BridgeTokensParams memory p = _signBridgeParams(1 ether, 0, bytes32(uint256(uint160(0xC0DE))), far, bytes32(uint256(0x6)));

        vm.warp(block.timestamp + 3650 days);

        vm.prank(user);
        bridge.bridgeTokens{ value: 1 ether }(p);

        console.log("block.timestamp at submission =", block.timestamp);
        console.log("IMPACT: signature minted in 2026 still redeemable a decade later");
    }

    /* ------------------------------------------------------------------ */
    /* M3 - unaccounted ETH via receive()  [claimed DoS]                    */
    /* ------------------------------------------------------------------ */

    function test_M3_receive_does_not_inflate_gasAccumulated() public {
        _registerCoinDepositMapping();

        IBridge.BridgeTokensParams memory p =
            _signBridgeParams(1 ether, 1 ether, bytes32(uint256(uint160(0xC0DE))), uint64(block.timestamp + 1 hours), bytes32(uint256(0x7)));

        vm.prank(user);
        bridge.bridgeTokens{ value: 2 ether }(p);

        assertEq(bridge.gasAccumulated(), 1 ether, "gasAccumulated after deposit");

        vm.deal(address(0xD057), 10_000 ether);
        vm.prank(address(0xD057));
        (bool ok,) = address(bridge).call{ value: 5 ether }("");
        require(ok, "receive must accept");

        assertEq(bridge.gasAccumulated(), 1 ether, "donation did NOT inflate gasAccumulated");
        console.log("after 5 ETH donation, gasAccumulated =", bridge.gasAccumulated());
    }

    function test_M3_donation_does_not_block_withdrawGasAccumulated() public {
        _registerCoinDepositMapping();

        IBridge.BridgeTokensParams memory p =
            _signBridgeParams(1 ether, 1 ether, bytes32(uint256(uint160(0xC0DE))), uint64(block.timestamp + 1 hours), bytes32(uint256(0x8)));

        vm.prank(user);
        bridge.bridgeTokens{ value: 2 ether }(p);

        // 200 separate 1-wei dust sends, the shape of the claimed griefing attack.
        for (uint256 i = 0; i < 200; i++) {
            address duster = address(uint160(0x1000 + i));
            vm.deal(duster, 1);
            vm.prank(duster);
            (bool ok,) = address(bridge).call{ value: 1 }("");
            require(ok, "dust send must be accepted");
        }

        uint256 balBefore = emergency.balance;
        vm.prank(emergency);
        bridge.withdrawGasAccumulated();

        assertEq(emergency.balance - balBefore, 1 ether, "emergency withdrew full gasAccumulated");
        assertEq(bridge.gasAccumulated(), 0, "counter reset");
        console.log("REFUTATION: 200 dust sends did not impede withdrawGasAccumulated");
    }

    function test_M3_donation_becomes_withdrawable_bridge_liquidity() public {
        vm.deal(address(0xD057), 1_000 ether);
        vm.prank(address(0xD057));
        (bool ok,) = address(bridge).call{ value: 777 ether }("");
        require(ok);

        assertEq(address(bridge).balance, 777 ether, "donation held as raw balance");
        assertEq(bridge.gasAccumulated(), 0, "never accounted");

        // withdrawCoinLiquidity treats the donation as bridge liquidity and can move it.
        vm.prank(multisig);
        bridge.withdrawCoinLiquidity(
            IBridge.WithdrawCoinLiquidityParams({ recipientAddress: multisig, amount: 777 ether })
        );
        assertEq(address(bridge).balance, 0, "donation swept by multisig");
        console.log("REAL behaviour: unaccounted ETH is silently treated as bridge liquidity");
    }

    /* ------------------------------------------------------------------ */
    /* M4 - claimed ETH lock when _validateECDSA reverts                    */
    /* ------------------------------------------------------------------ */

    function test_M4_failed_signature_refunds_msg_value() public {
        _registerCoinDepositMapping();

        IBridge.BridgeTokensParams memory p =
            _signBridgeParams(1 ether, 0, bytes32(uint256(uint160(0xC0DE))), uint64(block.timestamp - 1), bytes32(uint256(0x9)));

        vm.deal(user, 10 ether);
        uint256 userBefore = user.balance;
        uint256 bridgeBefore = address(bridge).balance;

        vm.prank(user);
        (bool ok,) = address(bridge).call{ value: 1 ether }(abi.encodeCall(IBridge.bridgeTokens, (p)));

        assertFalse(ok, "call must revert");
        assertEq(user.balance, userBefore, "user ETH fully refunded");
        assertEq(address(bridge).balance, bridgeBefore, "bridge holds no stray ETH");
        assertEq(bridge.gasAccumulated(), 0, "no accounting side effect");
        console.log("REFUTATION: expired-signature revert returned the full 1 ETH to the depositor");
    }

    function test_M4_failed_signature_wrong_signer_refunds_msg_value() public {
        _registerCoinDepositMapping();

        bytes32 h = _computeBridgeHash(
            user, USER_TO, bytes32(uint256(uint160(0xC0DE))), 0, 1 ether, block.chainid, 2, uint64(block.timestamp + 1 hours), bytes32(uint256(0xA))
        );
        (uint8 v, bytes32 r, bytes32 s) = _signHash(multisigPrivateKey, h); // wrong key

        IBridge.BridgeTokensParams memory p = IBridge.BridgeTokensParams({
            bridgeParams: IBridge.BridgeParams({ mapId: 1, amount: 1 ether, toAddress: USER_TO }),
            ECDSAParams: IBridge.ECDSAParams({ r: r, s: s, salt: bytes32(uint256(0xA)), deadline: uint64(block.timestamp + 1 hours), v: v })
        });

        vm.deal(user, 10 ether);
        uint256 userBefore = user.balance;

        vm.prank(user);
        (bool ok,) = address(bridge).call{ value: 1 ether }(abi.encodeCall(IBridge.bridgeTokens, (p)));

        assertFalse(ok, "call must revert");
        assertEq(user.balance, userBefore, "user ETH fully refunded");
        console.log("REFUTATION: non-relayer signer revert also refunded the full 1 ETH");
    }

    /* ------------------------------------------------------------------ */
    /* M5 - receiveTokens has no on-chain replay protection                 */
    /* ------------------------------------------------------------------ */

    function test_M5_receiveTokens_replayable_with_identical_externalId() public {
        FalseReturnERC20 token = new FalseReturnERC20();

        vm.startPrank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 2,
            targetChainId: block.chainid,
            depositType: IMapper.DepositType.None,
            withdrawType: IMapper.WithdrawType.Unlock,
            originTokenAddress: bytes32(uint256(uint160(0xDEAD))),
            targetTokenAddress: bytes32(uint256(uint160(address(token)))),
            useTransfer: false,
            isAllowed: true,
            isCoin: false
        }));
        bridge.setDailyLimit(bytes32(uint256(uint160(address(token)))), relayer, 1_000_000 ether);
        vm.stopPrank();

        token.mint(address(bridge), 10_000 ether);

        IBridge.ReceiveTokensParams memory p = IBridge.ReceiveTokensParams({
            externalId: bytes32(uint256(0xEEEA7)),
            mapId: 1,
            amount: 1_000 ether,
            fromAddress: bytes32(uint256(uint160(user))),
            toAddress: bytes32(uint256(uint160(user)))
        });

        address recipient = address(uint160(uint256(p.toAddress)));

        vm.prank(relayer);
        bridge.receiveTokens(p);
        assertEq(token.balanceOf(recipient), 1_000 ether, "first withdrawal settled");

        vm.prank(relayer);
        bridge.receiveTokens(p);
        assertEq(token.balanceOf(recipient), 2_000 ether, "IDENTICAL externalId paid twice");

        vm.prank(relayer);
        bridge.receiveTokens(p);
        assertEq(token.balanceOf(recipient), 3_000 ether, "and a third time");

        console.log("same externalId honoured 3x, recipient got:", token.balanceOf(recipient));
        console.log("usedHashes entries after 3 replays:", bridge.usedHashes(bytes32(uint256(0))));
    }

    /* ------------------------------------------------------------------ */
    /* M6 - destination bytes32 silently truncated to 160 bits              */
    /* ------------------------------------------------------------------ */

    function test_M6_nonzero_bytes32_truncates_to_zero_address() public {
        vm.startPrank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 2,
            targetChainId: block.chainid,
            depositType: IMapper.DepositType.None,
            withdrawType: IMapper.WithdrawType.Unlock,
            originTokenAddress: bytes32(uint256(uint160(0xDEAD))),
            targetTokenAddress: bytes32(uint256(uint160(0xC01E))),
            useTransfer: false,
            isAllowed: true,
            isCoin: true
        }));
        bridge.setDailyLimit(bytes32(0), relayer, 1_000_000 ether);
        vm.stopPrank();

        vm.deal(address(bridge), 10_000 ether);

        // Passes nonZeroBytes32, but the low 160 bits are zero.
        bytes32 malformed = bytes32(uint256(1) << 160);

        vm.prank(relayer);
        bridge.receiveTokens(IBridge.ReceiveTokensParams({
            externalId: bytes32(uint256(0xB)),
            mapId: 1,
            amount: 500 ether,
            fromAddress: bytes32(uint256(uint160(user))),
            toAddress: malformed
        }));

        assertEq(address(bridge).balance, 9_500 ether, "500 ETH left the bridge");
        assertEq(address(0).balance, 500 ether, "500 ETH burned at the zero address, no revert");
        console.log("toAddress as uint256:", uint256(malformed));
        console.log("resolved recipient:", address(uint160(uint256(malformed))));
        console.log("ETH now held by address(0):", address(0).balance);
    }
}
