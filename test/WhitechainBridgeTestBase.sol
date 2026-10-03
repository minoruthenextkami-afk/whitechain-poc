// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import { Test } from "forge-std/Test.sol";
import { Bridge } from "../../ether/contracts/main/modules/bridge/Bridge.sol";
import { Mapper } from "../../ether/contracts/main/modules/mapper/Mapper.sol";
import { IMapper } from "../../ether/contracts/main/modules/mapper/interfaces/IMapper.sol";
import { IBridge } from "../../ether/contracts/main/modules/bridge/interfaces/IBridge.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract WhitechainBridgeTestBase is Test {
    Bridge public bridge;
    Mapper public mapper;

    uint256 public relayerPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 public multisigPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public emergencyPrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
    address public relayer;
    address public multisig;
    address public emergency;

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    function _signHash(uint256 privateKey, bytes32 hash)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (v, r, s) = vm.sign(privateKey, messageHash);
    }

    function _computeBridgeHash(
        address caller,
        bytes32 toAddress,
        bytes32 targetTokenAddress,
        uint256 gasAmount,
        uint256 amount,
        uint256 originChainId,
        uint256 targetChainId,
        uint64 deadline,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                caller,
                toAddress,
                targetTokenAddress,
                gasAmount,
                amount,
                originChainId,
                targetChainId,
                deadline,
                salt
            )
        );
    }

    function _deployBridge(uint256 relayerKey) internal {
        relayer = vm.addr(relayerKey);
        multisig = vm.addr(multisigPrivateKey);
        emergency = vm.addr(emergencyPrivateKey);

        Mapper mapperImpl = new Mapper();
        bytes memory mapperInit = abi.encodeWithSignature(
            "initialize((address,address))",
            emergency,
            multisig
        );
        ERC1967Proxy mapperProxy = new ERC1967Proxy(address(mapperImpl), mapperInit);
        mapper = Mapper(address(mapperProxy));

        Bridge bridgeImpl = new Bridge();
        bytes memory bridgeInit = abi.encodeWithSignature(
            "initialize((address,address,address,address))",
            address(mapper),
            emergency,
            multisig,
            relayer
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(bridgeImpl), bridgeInit);
        bridge = Bridge(payable(address(bridgeProxy)));
        vm.stopPrank();
    }

    function _getMapInfo(uint256 mapId) internal view returns (IMapper.MapInfo memory) {
        (
            uint256 originChainId,
            uint256 targetChainId,
            IMapper.DepositType depositType,
            IMapper.WithdrawType withdrawType,
            bytes32 originTokenAddress,
            bytes32 targetTokenAddress,
            bool useTransfer,
            bool isAllowed,
            bool isCoin
        ) = mapper.mapInfo(mapId);

        return IMapper.MapInfo({
            originChainId: originChainId,
            targetChainId: targetChainId,
            depositType: depositType,
            withdrawType: withdrawType,
            originTokenAddress: originTokenAddress,
            targetTokenAddress: targetTokenAddress,
            useTransfer: useTransfer,
            isAllowed: isAllowed,
            isCoin: isCoin
        });
    }

    function _registerDepositMapping(
        address originToken,
        address targetToken,
        IMapper.DepositType depositType
    ) internal {
        vm.startPrank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: block.chainid,
            targetChainId: 2,
            depositType: depositType,
            withdrawType: IMapper.WithdrawType.None,
            originTokenAddress: bytes32(uint256(uint160(originToken))),
            targetTokenAddress: bytes32(uint256(uint160(targetToken))),
            useTransfer: false,
            isAllowed: true,
            isCoin: false
        }));
        vm.stopPrank();
    }

    function _registerWithdrawalMapping(
        address originToken,
        address targetToken,
        IMapper.WithdrawType withdrawType,
        bool isCoin
    ) internal {
        vm.startPrank(multisig);
        mapper.registerMapping(IMapper.MapInfo({
            originChainId: 2,
            targetChainId: block.chainid,
            depositType: IMapper.DepositType.None,
            withdrawType: withdrawType,
            originTokenAddress: bytes32(uint256(uint160(originToken))),
            targetTokenAddress: bytes32(uint256(uint160(targetToken))),
            useTransfer: false,
            isAllowed: true,
            isCoin: isCoin
        }));
        vm.stopPrank();
    }
}
