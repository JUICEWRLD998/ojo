// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {OjoParty} from "../src/OjoParty.sol";
import {BundleDesk} from "../src/BundleDesk.sol";
import {MockERC3009} from "../test/mocks/MockERC3009.sol";

/// Deploys OjoParty and BundleDesk.
///  - Monad mainnet (143): wires the real AUSD and USDC.
///  - Monad testnet (10143): no AUSD or USDC exist there, so it deploys two mintable mocks and mints 1,000 of each to
///    GUEST_ADDRESS for the end-to-end rehearsal. The mocks are for testnet only and must never be used on mainnet.
/// Run: forge script script/Deploy.s.sol --rpc-url <url> --broadcast --network monad
contract Deploy is Script {
    address constant AUSD_MAINNET = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
    address constant USDC_MAINNET = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address ausd;
        address usdc;

        vm.startBroadcast(pk);
        if (block.chainid == 143) {
            ausd = AUSD_MAINNET;
            usdc = USDC_MAINNET;
        } else if (block.chainid == 10143) {
            address guest = vm.envAddress("GUEST_ADDRESS");
            MockERC3009 a = new MockERC3009("Agora Dollar");
            MockERC3009 u = new MockERC3009("USD Coin");
            a.mint(guest, 1_000e6);
            u.mint(guest, 1_000e6);
            ausd = address(a);
            usdc = address(u);
        } else {
            revert("unsupported chain: expected 143 or 10143");
        }
        OjoParty party = new OjoParty(ausd, usdc);
        BundleDesk desk = new BundleDesk(ausd, usdc);
        vm.stopBroadcast();

        console2.log("chainId   ", block.chainid);
        console2.log("AUSD      ", ausd);
        console2.log("USDC      ", usdc);
        console2.log("OjoParty  ", address(party));
        console2.log("BundleDesk", address(desk));
    }
}
