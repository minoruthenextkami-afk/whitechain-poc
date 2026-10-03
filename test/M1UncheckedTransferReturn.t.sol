// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import {Test} from "forge-std/Test.sol";
import {Bridge} from "lib/whitechain/contracts/main/modules/bridge/Bridge.sol";
import {Mapper} from "lib/whitechain/contracts/main/modules/mapper/Mapper.sol";
import {IBridge} from "lib/whitechain/contracts/main/modules/bridge/interfaces/IBridge.sol";
import {IMapper} from "lib/whitechain/contracts/main/modules/mapper/interfaces/IMapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BrokenERC20 is ERC20 {
    bool public revertOnTransfer;

    constructor(uint256 _ownerBalance) ERC20("Broken", "BRK") {
        _mint(msg.sender, _ownerBalance);
    }

    function setRevertOnTransfer(bool _revert) external {
        revertOnTransfer = _revert;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (revertOnTransfer) {
            return false;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (revertOnTransfer) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

contract M1UncheckedTransferReturn is Test {
    function testReceiveTokensTransferReturnsFalseButEventStillEmitted() public {
        address RELAYER = address(0x1);
        address MULTISIG = address(0x2);
        address EMERGENCY = address(0x3);
        address TO = address(0x4);

        BrokenERC20 token = new BrokenERC20(1_000_000 ether);

        Mapper mapper = new Mapper();
        mapper.initialize(IMapper.InitParams({ multisigAddress: MULTISIG, emergencyAddress: EMERGENCY }));

        Bridge bridge = new Bridge();
        bridge.initialize(IBridge.InitParams({
            mapperAddress: address(mapper),
            emergencyAddress: EMERGENCY,
            multisigAddress: MULTISIG,
            relayerAddress: RELAYER
        }));

        vm.chainId(1874);
        vm.startPrank(MULTISIG);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 11155111,
            targetChainId: 1874,
            depositType: IMapper.DepositType.None,
            withdrawType: IMapper.WithdrawType.Unlock,
            originTokenAddress: bytes32(0),
            targetTokenAddress: bytes32(uint256(uint160(address(token)))),
            useTransfer: true,
            isAllowed: true,
            isCoin: false
        }));
        vm.stopPrank();

        vm.deal(RELAYER, 10 ether);
        vm.deal(address(bridge), 1 ether);

        uint256 amount = 1000 ether;
        token.setRevertOnTransfer(true);

        vm.startPrank(RELAYER);
        vm.expectEmit(true, true, false, true);
        emit IBridge.Withdrawal({
            fromAddress: bytes32(0),
            toAddress: bytes32(uint256(uint160(TO))),
            targetTokenAddress: bytes32(uint256(uint160(address(token)))),
            originTokenAddress: bytes32(0),
            externalId: bytes32(0),
            amount: amount,
            originChainId: 11155111,
            targetChainId: 1874
        });

        bridge.receiveTokens(IBridge.ReceiveTokensParams({
            externalId: bytes32(0),
            fromAddress: bytes32(0),
            toAddress: bytes32(uint256(uint160(TO))),
            mapId: 1,
            amount: amount
        }));
        vm.stopPrank();

        assertEq(token.balanceOf(TO), 0, "recipient should have zero tokens because transfer returned false");
        assertEq(token.balanceOf(address(bridge)), 0, "bridge should have zero tokens because transfer returned false");
    }

    function testReceiveTokensSafeTransferSucceeds() public {
        address RELAYER = address(0x1);
        address MULTISIG = address(0x2);
        address EMERGENCY = address(0x3);
        address TO = address(0x4);

        BrokenERC20 token = new BrokenERC20(1_000_000 ether);

        Mapper mapper = new Mapper();
        mapper.initialize(IMapper.InitParams({ multisigAddress: MULTISIG, emergencyAddress: EMERGENCY }));

        Bridge bridge = new Bridge();
        bridge.initialize(IBridge.InitParams({
            mapperAddress: address(mapper),
            emergencyAddress: EMERGENCY,
            multisigAddress: MULTISIG,
            relayerAddress: RELAYER
        }));

        vm.chainId(1874);
        vm.startPrank(MULTISIG);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 11155111,
            targetChainId: 1874,
            depositType: IMapper.DepositType.None,
            withdrawType: IMapper.WithdrawType.Unlock,
            originTokenAddress: bytes32(0),
            targetTokenAddress: bytes32(uint256(uint160(address(token)))),
            useTransfer: true,
            isAllowed: true,
            isCoin: false
        }));
        vm.stopPrank();

        vm.deal(RELAYER, 10 ether);
        vm.deal(address(bridge), 1 ether);

        uint256 amount = 1000 ether;

        vm.startPrank(RELAYER);
        vm.expectEmit(true, true, false, true);
        emit IBridge.Withdrawal({
            fromAddress: bytes32(0),
            toAddress: bytes32(uint256(uint160(TO))),
            targetTokenAddress: bytes32(uint256(uint160(address(token)))),
            originTokenAddress: bytes32(0),
            externalId: bytes32(0),
            amount: amount,
            originChainId: 11155111,
            targetChainId: 1874
        });

        bridge.receiveTokens(IBridge.ReceiveTokensParams({
            externalId: bytes32(0),
            fromAddress: bytes32(0),
            toAddress: bytes32(uint256(uint160(TO))),
            mapId: 1,
            amount: amount
        }));
        vm.stopPrank();

        assertEq(token.balanceOf(TO), amount, "recipient should have tokens");
    }
}
