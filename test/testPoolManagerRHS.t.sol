// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {PoolManagerRootHash} from "../src/core/PoolManagerRootHash.sol";
import {MessageManager} from "../src/core/MessageManager.sol";
import {mockToken} from "../script/utils/mockERC20.sol";
import {USDCToken} from "../src/token/Wrapped/USDC.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/interfaces/IPoolManager.sol";

contract PoolManagerRHSTest is Test {
    PoolManagerRootHash public sourcePoolManager;
    PoolManager public destPoolManager;
    MessageManager public sourceMessageManager;
    MessageManager public destMessageManager;

    mockToken public erc20Token;
    USDCToken public usdcTokenImple;
    USDCToken public usdcToken;
    address public constant NativeTokenAddress =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint256 constant SOURCE_CHAIN_ID = 1;
    uint256 constant DEST_CHAIN_ID = 10;

    address cat = makeAddr("cat");
    address seek = makeAddr("seek");

    address bridge_cat = makeAddr("bridge_cat");
    address bridge_seek = makeAddr("bridge_seek");

    address admin;
    address ReLayer;

    function setUp() public {
        admin = makeAddr("admin");
        ReLayer = makeAddr("ReLayer");

        vm.deal(admin, 1000 ether);
        vm.deal(ReLayer, 1000 ether);
        vm.deal(cat, 1000 ether);

        PoolManager poolManagerLogic = new PoolManager();
        PoolManagerRootHash poolManagerRHLogic = new PoolManagerRootHash();
        MessageManager messageManagerLogic = new MessageManager();
        erc20Token = new mockToken("CAT", "CAT");
        usdcTokenImple = new USDCToken();

        vm.startPrank(admin);
        TransparentUpgradeableProxy sourcePoolManagerProxy = new TransparentUpgradeableProxy(
                address(poolManagerRHLogic),
                admin,
                ""
            );
        TransparentUpgradeableProxy sourceMessageManagerProxy = new TransparentUpgradeableProxy(
                address(messageManagerLogic),
                admin,
                ""
            );
        TransparentUpgradeableProxy destPoolManagerProxy = new TransparentUpgradeableProxy(
                address(poolManagerLogic),
                admin,
                ""
            );
        TransparentUpgradeableProxy destMessageManagerProxy = new TransparentUpgradeableProxy(
                address(messageManagerLogic),
                admin,
                ""
            );

        TransparentUpgradeableProxy usdcTokenProxy = new TransparentUpgradeableProxy(
                address(usdcTokenImple),
                admin,
                ""
            );

        usdcToken = USDCToken(address(usdcTokenProxy));
        usdcToken.initialize(ReLayer);
        sourcePoolManager = PoolManagerRootHash(
            payable(address(sourcePoolManagerProxy))
        );
        destPoolManager = PoolManager(payable(address(destPoolManagerProxy)));
        sourceMessageManager = MessageManager(
            address(sourceMessageManagerProxy)
        );
        destMessageManager = MessageManager(address(destMessageManagerProxy));

        sourcePoolManager.initialize(
            admin,
            address(sourceMessageManager),
            ReLayer,
            admin
        );
        destPoolManager.initialize(
            admin,
            address(destMessageManager),
            ReLayer,
            admin
        );
        sourceMessageManager.initialize(admin, address(sourcePoolManager));
        destMessageManager.initialize(admin, address(destPoolManager));
        vm.stopPrank();

        vm.startPrank(ReLayer);
        usdcToken.mint(cat, 1000 ether);
        usdcToken.setBridgeAddress(address(sourcePoolManager));
        sourcePoolManager.setValidChainId(DEST_CHAIN_ID, true);
        sourcePoolManager.setTokenUSDTExchangeRate(1e5, address(erc20Token)); // 1 USDT = 10 CAT
        destPoolManager.setValidChainId(SOURCE_CHAIN_ID, true);
        sourcePoolManager.setPerFee(
            3000,
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ); // 0.3%
        destPoolManager.setPerFee(
            3000,
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ); // 0.3%
        sourcePoolManager.setPerFee(3000, address(erc20Token)); // 0.3%
        destPoolManager.setPerFee(3000, address(erc20Token)); // 0.3%
        sourcePoolManager.setSupportERC20Token(address(erc20Token), true);
        destPoolManager.setSupportERC20Token(address(erc20Token), true);
        sourcePoolManager.setSupportERC20Token(NativeTokenAddress, true);
        destPoolManager.setSupportERC20Token(NativeTokenAddress, true);
        sourcePoolManager.setSupportERC20Token(address(usdcToken), true);
        destPoolManager.setSupportERC20Token(address(usdcToken), true);
        // sourcePoolManager.setMaxTransferAmount(1000 ether, false);
        sourcePoolManager.depositNativeTokenToBridge{value: 500 ether}(); // 起始原始代币储备500 ETH
        destPoolManager.depositNativeTokenToBridge{value: 500 ether}();

        mockToken(address(erc20Token)).mint(cat, 1000 ether);
        vm.stopPrank();

        vm.startPrank(cat);
        usdcToken.approve(address(sourcePoolManager), 1000 ether);
        erc20Token.approve(address(sourcePoolManager), 1000 ether);
        erc20Token.approve(address(destPoolManager), 1000 ether);
        sourcePoolManager.depositErc20ToBridge(address(erc20Token), 200 ether); // 起始erc20储备200 e18
        destPoolManager.depositErc20ToBridge(address(erc20Token), 200 ether);
        vm.stopPrank();
    }

    // Test bridging ETH from source to destination chain
    function test_Bridge_ETH() public {
        _bridge_ETH(10, cat, seek);
    }

    // Test bridging ERC20 tokens from source to destination chain
    function test_Bridge_ERC20() public {
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(address(erc20Token), true);
        destPoolManager.setSupportERC20Token(address(erc20Token), true);
        vm.stopPrank();

        _bridge_ERC20(10, cat, seek);
    }

    function test_Bridge_WrappedERC20() public {
        address wrappedToken = address(usdcToken);
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(wrappedToken, true);
        destPoolManager.setSupportERC20Token(wrappedToken, true);
        vm.stopPrank();

        _bridge_WrappedERC20(10, cat, seek);

        assertEq(usdcToken.balanceOf(cat), 990 ether);
        assertEq(usdcToken.totalSupply(), 990 ether);
    }

    function _bridge_ETH(uint256 amount, address from, address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        vm.deal(from, bridgeAmount);

        address ethTokenAddress = address(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        );
        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(
            ethTokenAddress
        );
        uint256 nextMessageNumberBefore = sourceMessageManager
            .nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.prank(from);
        sourcePoolManager.BridgeInitiateNativeToken{value: bridgeAmount}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            ethTokenAddress,
            seek
        );

        assertEq(
            sourcePoolManager.FundingPoolBalance(ethTokenAddress),
            balanceBefore + bridgeAmount,
            "FundingPoolBalance for ETH should increase by bridgeAmount"
        );
        assertEq(
            sourceMessageManager.nextMessageNumber(),
            nextMessageNumberBefore + 1,
            "nextMessageNumber should be incremented"
        );

        uint256 perFee = sourcePoolManager.PerFee(ethTokenAddress);
        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = nextMessageNumberBefore;
        bytes32 messageHash = keccak256(
            abi.encode(
                SOURCE_CHAIN_ID,
                DEST_CHAIN_ID,
                ethTokenAddress,
                ethTokenAddress,
                from,
                to,
                fee,
                amountAfterFee,
                messageNonce
            )
        );

        assertTrue(
            sourceMessageManager.sentMessageStatus(messageHash),
            "Message hash should be marked as sent"
        );
    }

    function _bridge_ERC20(uint256 amount, address from, address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        erc20Token.mint(from, bridgeAmount);

        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(
            address(erc20Token)
        );
        uint256 nextMessageNumberBefore = sourceMessageManager
            .nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(from);
        erc20Token.approve(address(sourcePoolManager), bridgeAmount);
        sourcePoolManager.BridgeInitiateERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            to,
            address(erc20Token),
            address(erc20Token),
            bridgeAmount
        );
        vm.stopPrank();

        assertEq(
            erc20Token.balanceOf(address(sourcePoolManager)),
            balanceBefore + bridgeAmount,
            "Contract ERC20 balance should equal bridgeAmount"
        );
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(erc20Token)),
            balanceBefore + bridgeAmount,
            "FundingPoolBalance for ERC20 should equal bridgeAmount"
        );
        assertEq(
            sourceMessageManager.nextMessageNumber(),
            nextMessageNumberBefore + 1,
            "nextMessageNumber should be incremented"
        );

        uint256 perFee = sourcePoolManager.PerFee(address(erc20Token));
        uint256 tokenUsdtRate = sourcePoolManager.TokenUSDTExchangeRate(
            address(erc20Token)
        );
        uint256 usdtAmount = (bridgeAmount * tokenUsdtRate) / (1e6 * 1e12); // 1e6 for USDT, 1e18 for CAT
        uint256 fee = (usdtAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = usdtAmount - fee;

        uint256 messageNonce = 1;
        bytes32 messageHash = keccak256(
            abi.encode(
                SOURCE_CHAIN_ID,
                DEST_CHAIN_ID,
                address(erc20Token),
                address(erc20Token),
                from,
                to,
                fee,
                amountAfterFee,
                messageNonce
            )
        );

        assertTrue(
            sourceMessageManager.sentMessageStatus(messageHash),
            "Message hash for ERC20 bridge should be marked as sent"
        );
    }

    function _bridge_WrappedERC20(
        uint256 amount,
        address from,
        address to
    ) internal {
        uint256 bridgeAmount = amount * 1 ether;

        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(
            address(usdcToken)
        );
        assertEq(balanceBefore, 0);

        uint256 nextMessageNumberBefore = sourceMessageManager
            .nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(from);

        sourcePoolManager.BridgeInitiateWrappedERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            to,
            address(usdcToken),
            address(usdcToken),
            bridgeAmount
        );
        vm.stopPrank();

        assertEq(
            usdcToken.balanceOf(address(sourcePoolManager)),
            0,
            "Contract WrappedERC20 balance should equal 0"
        );
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(usdcToken)),
            0,
            "FundingPoolBalance for ERC20 should equal 0"
        );
        assertEq(
            sourceMessageManager.nextMessageNumber(),
            nextMessageNumberBefore + 1,
            "nextMessageNumber should be incremented"
        );

        uint256 perFee = sourcePoolManager.PerFee(address(usdcToken));

        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = 1;
        bytes32 messageHash = keccak256(
            abi.encode(
                SOURCE_CHAIN_ID,
                DEST_CHAIN_ID,
                address(usdcToken),
                address(usdcToken),
                from,
                to,
                fee,
                amountAfterFee,
                messageNonce
            )
        );

        assertTrue(
            sourceMessageManager.sentMessageStatus(messageHash),
            "Message hash for ERC20 bridge should be marked as sent"
        );
    }

    function test_Revert_Bridge_Unsupported_Token() public {
        address unsupportedToken = address(
            0x1234567890123456789012345678901234567890
        );
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(unsupportedToken, false);
        vm.stopPrank();

        uint256 bridgeAmount = 10 ether;
        erc20Token.mint(cat, bridgeAmount);

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(cat);
        erc20Token.approve(address(sourcePoolManager), bridgeAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.TokenIsNotSupported.selector, // 注意这里是 `.selector`
                unsupportedToken
            )
        );
        sourcePoolManager.BridgeInitiateERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            seek,
            unsupportedToken,
            unsupportedToken,
            bridgeAmount
        );
        vm.stopPrank();
    }

    function test_depositNativeTokenToBridge() public {
        vm.deal(address(sourcePoolManager), 100 ether);
        vm.deal(address(destPoolManager), 100 ether);
        vm.prank(admin);
        sourcePoolManager.depositNativeTokenToBridge{value: 100 ether}();
        vm.prank(admin);
        destPoolManager.depositNativeTokenToBridge{value: 100 ether}();
        assertEq(address(sourcePoolManager).balance, 200 ether);
        assertEq(address(destPoolManager).balance, 200 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(NativeTokenAddress),
            600 ether
        );
        assertEq(
            destPoolManager.FundingPoolBalance(NativeTokenAddress),
            600 ether
        );
    }

    function test_depositErc20ToBridge() public {
        erc20Token.mint(address(sourcePoolManager), 100 ether);
        erc20Token.mint(address(destPoolManager), 100 ether);
        vm.prank(cat);
        sourcePoolManager.depositErc20ToBridge(address(erc20Token), 100 ether);
        vm.prank(cat);
        destPoolManager.depositErc20ToBridge(address(erc20Token), 100 ether);
        assertEq(erc20Token.balanceOf(address(sourcePoolManager)), 400 ether);
        assertEq(erc20Token.balanceOf(address(destPoolManager)), 400 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(erc20Token)),
            300 ether
        );
        assertEq(
            destPoolManager.FundingPoolBalance(address(erc20Token)),
            300 ether
        );
    }

    function test_withdrawNativeTokenFromBridge() public {
        uint256 beforeBalance = admin.balance;
        vm.prank(admin);
        sourcePoolManager.withdrawNativeTokenFromBridge(
            payable(admin),
            100 ether
        );
        assertEq(admin.balance, beforeBalance + 100 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(NativeTokenAddress),
            400 ether
        );

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        sourcePoolManager.withdrawNativeTokenFromBridge(
            payable(cat),
            100 ether
        );
    }

    function test_withdrawErc20FromBridge() public {
        uint256 beforeBalance = erc20Token.balanceOf(admin);
        vm.prank(admin);
        sourcePoolManager.withdrawErc20FromBridge(
            address(erc20Token),
            admin,
            100 ether
        );
        assertEq(erc20Token.balanceOf(admin), beforeBalance + 100 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(erc20Token)),
            100 ether
        );

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        sourcePoolManager.withdrawErc20FromBridge(
            address(erc20Token),
            cat,
            100
        );
    }

    function test_setMinandMaxTransferAmount() public {
        vm.prank(ReLayer);
        sourcePoolManager.setMinTransferAmount(1 ether);
        assertEq(sourcePoolManager.MinTransferAmount(), 1 ether);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setMinTransferAmount(2 ether);
    }

    function test_setMaxTransferAmount() public {
        vm.startPrank(ReLayer);
        sourcePoolManager.setMaxTransferAmount(1000 ether, false);
        assertEq(sourcePoolManager.MaxPointsTransferAmount(), 1000 ether);
        sourcePoolManager.setMaxTransferAmount(5000 ether, true);
        assertEq(sourcePoolManager.MaxERC20TransferAmount(), 5000 ether);
        vm.stopPrank();

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.setMaxTransferAmount(2000 ether, true);
    }

    function test_setValidChainId() public {
        vm.prank(ReLayer);
        sourcePoolManager.setValidChainId(999, true);
        assertTrue(sourcePoolManager.IsSupportedChainId(999));

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setValidChainId(998, true);
    }

    function test_setSupportERC20Token() public {
        address newToken = address(0x1234567890123456789012345678901234567890);
        vm.prank(ReLayer);
        sourcePoolManager.setSupportERC20Token(newToken, true);
        assertTrue(sourcePoolManager.IsSupportToken(newToken));
        assertEq(sourcePoolManager.SupportTokens(3), newToken);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setSupportERC20Token(newToken, false);
    }

    function test_setPerFee() public {
        vm.prank(ReLayer);
        sourcePoolManager.setPerFee(5000, address(erc20Token));
        assertEq(sourcePoolManager.PerFee(address(erc20Token)), 5000);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setPerFee(6000, address(erc20Token));
    }

    function test_onlyOwnerCanPause() public {
        vm.prank(admin);
        sourcePoolManager.pause();
        assertTrue(sourcePoolManager.paused());

        vm.chainId(SOURCE_CHAIN_ID);
        vm.expectRevert();
        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 1 ether}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );

        vm.prank(admin);
        sourcePoolManager.unpause();
        assertFalse(sourcePoolManager.paused());

        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 1 ether}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );
        assertEq(
            sourcePoolManager.FundingPoolBalance(NativeTokenAddress),
            501 ether
        );
    }

    function test_QuickSendAssertToUser() public {
        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            address(erc20Token),
            seek,
            100 ether
        );
        assertTrue(
            erc20Token.balanceOf(address(sourcePoolManager)) == 100 ether
        );
        assertTrue(erc20Token.balanceOf(seek) == 100 ether);

        vm.expectRevert(
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        vm.prank(cat);
        sourcePoolManager.QuickSendAssertToUser(
            address(erc20Token),
            cat,
            100 ether
        );

        address unsupportedToken = address(
            0x1234567890123456789012345678901234567890
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.TokenIsNotSupported.selector, // 注意这里是 `.selector`
                unsupportedToken
            )
        );
        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            unsupportedToken,
            cat,
            100 ether
        );

        vm.expectRevert("Not enough balance");
        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            address(erc20Token),
            cat,
            10000 ether
        );

        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            NativeTokenAddress,
            seek,
            1 ether
        );
        assertTrue(seek.balance == 1 ether);
    }

    // ========== 3️⃣ Test finalize ETH by relayer ==========
    function test_Finalize_ETH() public {
        uint256 amount = 10 ether;
        vm.deal(address(sourcePoolManager), amount);

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(ReLayer);
        sourcePoolManager.BridgeFinalizeNativeToken(
            DEST_CHAIN_ID,
            SOURCE_CHAIN_ID,
            NativeTokenAddress,
            cat,
            seek,
            amount,
            0,
            1
        );
        vm.stopPrank();

        assertEq(seek.balance, amount, "Receiver should get bridged ETH");
    }

    // ========== 4️⃣ Test finalize ERC20 by relayer ==========
    function test_Finalize_ERC20() public {
        uint256 amount = 1e6;
        erc20Token.mint(address(sourcePoolManager), 100 ether);

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(ReLayer);
        sourcePoolManager.BridgeFinalizeERC20(
            DEST_CHAIN_ID,
            SOURCE_CHAIN_ID,
            cat,
            seek,
            address(erc20Token),
            address(erc20Token),
            amount,
            0,
            1
        );
        vm.stopPrank();

        assertEq(
            erc20Token.balanceOf(seek),
            10 ether,
            "Receiver should get bridged ERC20 tokens"
        );
    }

    function test_Finalize_WrappedERC20() public {
        uint256 amount = 1 ether;

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(ReLayer);
        sourcePoolManager.BridgeFinalizeWrappedERC20(
            DEST_CHAIN_ID,
            SOURCE_CHAIN_ID,
            cat,
            seek,
            address(usdcToken),
            address(usdcToken),
            amount,
            0,
            1
        );
        vm.stopPrank();

        assertEq(
            usdcToken.balanceOf(seek),
            1 ether,
            "Receiver should get bridged WrappedERC20 tokens"
        );
    }

    // ========== 5️⃣ Test unauthorized finalize revert ==========
    function test_Revert_Finalize_ETH_Unauthorized() public {
        uint256 amount = 5 ether;
        vm.deal(address(destPoolManager), amount);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        destPoolManager.BridgeFinalizeNativeToken(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            cat,
            seek,
            amount,
            0,
            1
        );
    }

    // ========== 6️⃣ Test withdraw function by admin ==========
    function test_Withdraw_ETH() public {
        uint256 depositAmount = 5 ether;
        vm.deal(address(sourcePoolManager), depositAmount);

        uint256 beforeBalance = admin.balance;

        vm.prank(admin);
        sourcePoolManager.withdrawNativeTokenFromBridge(
            payable(admin),
            depositAmount
        );

        assertEq(admin.balance, beforeBalance + depositAmount);
    }

    // ========== 7️⃣ Test invalid chain revert ==========
    function test_Revert_InvalidChain() public {
        vm.deal(cat, 1 ether);
        vm.chainId(SOURCE_CHAIN_ID);

        vm.expectRevert();
        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 1 ether}(
            999, // wrong source chain id
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );
    }

    // ========== 8️⃣ Test less than min transfer amount revert ==========
    function test_Revert_LessThanMin() public {
        vm.deal(cat, 0.01 ether);
        vm.chainId(SOURCE_CHAIN_ID);

        vm.expectRevert();
        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 0.01 ether}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );
    }

    function test_IsSupportChainId() public view {
        assertTrue(sourcePoolManager.IsSupportedChainId(DEST_CHAIN_ID));
        assertFalse(sourcePoolManager.IsSupportedChainId(999));
    }
}
