// script/DeployMyToken.s.sol
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/token/RootHashChain/TWTest.sol";

contract DeployMyToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // 开启广播（相当于“发送交易”）
        vm.startBroadcast(deployerPrivateKey);

        // 部署合约
        TWTestToken token = new TWTestToken();
        token.initialize(0x546E28369957Ee809C611953a0597aC218d915f5);
        console.log("token address", address(token));

        vm.stopBroadcast();
    }
}
