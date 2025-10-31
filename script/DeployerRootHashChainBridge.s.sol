// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "./utils/EmptyContract.sol";
import {MessageManager} from "../src/core/MessageManager.sol";
import {PoolManagerRootHash} from "../src/core/PoolManagerRootHash.sol";

contract DeployerRootHashChainBridge is Script {
    EmptyContract public emptyContract;

    ProxyAdmin public messageManagerProxyAdmin;
    ProxyAdmin public poolManagerProxyAdmin;

    MessageManager public messageManager;
    MessageManager public messageManagerImplementation;

    PoolManagerRootHash public poolManager;
    PoolManagerRootHash public poolManagerImplementation;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address relayerAddress = vm.envAddress("RELAYER_ADDRESS");
        address rootHashChainMultiSign = vm.envAddress("MULTI_SIGNER");

        console.log("RELAYER_ADDRESS: ", relayerAddress);
        console.log("MULTI_SIGNER: ", rootHashChainMultiSign);

        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Depolyer Address: ", deployerAddress);
        vm.startBroadcast(deployerPrivateKey);

        emptyContract = new EmptyContract();

        TransparentUpgradeableProxy proxyMessageManager =
            new TransparentUpgradeableProxy(address(emptyContract), rootHashChainMultiSign, "");
        messageManager = MessageManager(address(proxyMessageManager));
        messageManagerImplementation = new MessageManager();
        messageManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyMessageManager)));

        TransparentUpgradeableProxy proxyPoolManager =
            new TransparentUpgradeableProxy(address(emptyContract), rootHashChainMultiSign, "");
        poolManager = PoolManagerRootHash(payable(address(proxyPoolManager)));
        poolManagerImplementation = new PoolManagerRootHash();
        poolManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyPoolManager)));

        messageManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(messageManager)),
            address(messageManagerImplementation),
            abi.encodeWithSelector(MessageManager.initialize.selector, relayerAddress, poolManager)
        );

        poolManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(poolManager)),
            address(poolManagerImplementation),
            abi.encodeWithSelector(
                PoolManagerRootHash.initialize.selector, relayerAddress, messageManager, relayerAddress, relayerAddress
            )
        );

        console.log("deploy proxyMessageManager:", address(proxyMessageManager));
        console.log("deploy proxyPoolManager:", address(proxyPoolManager));
        // string memory path = "deployed_addresses.json";
        // string memory data = string(abi.encodePacked(
        //     '{"proxyMessageManager": "', vm.toString(address(proxyMessageManager)), '", ',
        //     '"proxyPoolManager": "', vm.toString(address(proxyPoolManager)), '"}'
        // ));
        // vm.writeJson(data, path);
        // vm.stopBroadcast();
    }

    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
