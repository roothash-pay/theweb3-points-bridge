// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "./utils/EmptyContract.sol";
import {TWToken} from "../src/token/RootHashChain/TW.sol";
import {DAIToken} from "../src/token/Wrapped/DAI.sol";
import {USDCToken} from "../src/token/Wrapped/USDC.sol";
import {USDTToken} from "../src/token/Wrapped/USDT.sol";

contract DeployerRootHashChainToken is Script {
    EmptyContract public emptyContract;

    ProxyAdmin public tWTokenProxyAdmin;
    ProxyAdmin public daiTokenProxyAdmin;
    ProxyAdmin public usdcTokenProxyAdmin;
    ProxyAdmin public usdtTokenProxyAdmin;

    TWToken public tWToken;
    TWToken public tWTokenImplementation;
    DAIToken public daiToken;
    DAIToken public daiTokenImplementation;
    USDCToken public usdcToken;
    USDCToken public usdcTokenImplementation;
    USDTToken public usdtToken;
    USDTToken public usdtTokenImplementation;

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

        TransparentUpgradeableProxy proxyTWToken =
            new TransparentUpgradeableProxy(address(emptyContract), rootHashChainMultiSign, "");
        tWToken = TWToken(address(proxyTWToken));
        tWTokenImplementation = new TWToken();
        tWTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyTWToken)));

        TransparentUpgradeableProxy proxyDAIToken =
            new TransparentUpgradeableProxy(address(emptyContract), rootHashChainMultiSign, "");
        daiToken = DAIToken(address(proxyDAIToken));
        daiTokenImplementation = new DAIToken();
        daiTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyDAIToken)));

        TransparentUpgradeableProxy proxyUSDTToken =
            new TransparentUpgradeableProxy(address(emptyContract), rootHashChainMultiSign, "");
        usdtToken = USDTToken(address(proxyUSDTToken));
        usdtTokenImplementation = new USDTToken();
        usdtTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyUSDTToken)));

        TransparentUpgradeableProxy proxyUSDCToken =
            new TransparentUpgradeableProxy(address(emptyContract), rootHashChainMultiSign, "");
        usdcToken = USDCToken(address(proxyUSDCToken));
        usdcTokenImplementation = new USDCToken();
        usdcTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyUSDCToken)));

        // =========upgrade=============
        tWTokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(tWToken)),
            address(tWTokenImplementation),
            abi.encodeWithSelector(TWToken.initialize.selector, relayerAddress)
        );

        console.log("deploy TWToken:", address(tWToken));

        daiTokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(daiToken)),
            address(daiTokenImplementation),
            abi.encodeWithSelector(TWToken.initialize.selector, relayerAddress)
        );

        console.log("deploy DAIToken:", address(daiToken));

        usdcTokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdcToken)),
            address(usdcTokenImplementation),
            abi.encodeWithSelector(TWToken.initialize.selector, relayerAddress)
        );

        console.log("deploy USDCToken:", address(usdcToken));

        usdtTokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(usdtToken)),
            address(usdtTokenImplementation),
            abi.encodeWithSelector(TWToken.initialize.selector, relayerAddress)
        );

        console.log("deploy USDTToken:", address(usdtToken));
    }

    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
