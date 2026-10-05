// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Helpers} from "./Helpers.sol";
import {BundleDesk} from "../src/BundleDesk.sol";
import {MockERC3009} from "./mocks/MockERC3009.sol";

contract BundleDeskTest is Helpers {
    MockERC3009 usdc;
    MockERC3009 ausd;
    BundleDesk desk;

    uint256 vendorKey = 0x7E4D;
    uint256 voucherKey = 0x70C;
    uint256 attackerKey = 0xBAD;
    address vendor;
    address voucher;
    address attacker;
    address guest = address(0x6E57);
    bytes32 deskDomain;

    struct V {
        address vendor;
        address token;
        uint256 amount;
        address voucher;
        uint256 expiry;
    }

    event Deposited(address indexed vendor, address indexed token, uint256 amount);
    event Withdrawn(address indexed vendor, address indexed token, uint256 amount);
    event Claimed(address indexed vendor, address indexed to, address indexed token, uint256 amount, address voucher);

    function setUp() public {
        vm.warp(1_000_000);
        vendor = vm.addr(vendorKey);
        voucher = vm.addr(voucherKey);
        attacker = vm.addr(attackerKey);
        usdc = new MockERC3009("USD Coin");
        ausd = new MockERC3009("Agora Dollar");
        desk = new BundleDesk(address(ausd), address(usdc));
        deskDomain = _domain("BundleDesk", "1", address(desk));
        usdc.mint(vendor, 10_000e6);
        vm.prank(vendor);
        usdc.approve(address(desk), type(uint256).max);
    }

    // ---------- helpers ----------

    function _deposit(uint256 amount) internal {
        vm.prank(vendor);
        desk.deposit(address(usdc), amount);
    }

    function _v(uint256 amount) internal view returns (V memory) {
        return V(vendor, address(usdc), amount, voucher, block.timestamp + 1 days);
    }

    function _vDigest(V memory v) internal view returns (bytes32) {
        return _digest(
            deskDomain, keccak256(abi.encode(desk.VOUCHER_TYPEHASH(), v.vendor, v.token, v.amount, v.voucher, v.expiry))
        );
    }

    function _vendorSig(V memory v, uint256 key) internal view returns (bytes memory) {
        return _sig(key, _vDigest(v));
    }

    function _claimSig(V memory v, address to, uint256 key) internal view returns (bytes memory) {
        return _sig(key, _digest(deskDomain, keccak256(abi.encode(desk.CLAIM_TYPEHASH(), _vDigest(v), to))));
    }

    function _claim(V memory v, address to) internal {
        desk.claim(
            v.vendor, v.token, v.amount, v.voucher, v.expiry, to, _vendorSig(v, vendorKey), _claimSig(v, to, voucherKey)
        );
    }

    // ---------- deposit / withdraw ----------

    function test_deposit_credits() public {
        vm.expectEmit(true, true, false, true);
        emit Deposited(vendor, address(usdc), 100e6);
        _deposit(100e6);
        assertEq(desk.balanceOf(vendor, address(usdc)), 100e6);
        assertEq(usdc.balanceOf(address(desk)), 100e6);
    }

    function test_deposit_unsupportedTokenReverts() public {
        vm.prank(vendor);
        vm.expectRevert(BundleDesk.UnsupportedToken.selector);
        desk.deposit(address(0xDEAD), 1);
    }

    function test_deposit_zeroReverts() public {
        vm.prank(vendor);
        vm.expectRevert(BundleDesk.ZeroAmount.selector);
        desk.deposit(address(usdc), 0);
    }

    function test_deposit_withoutApprovalReverts() public {
        ausd.mint(vendor, 5e6);
        vm.prank(vendor);
        vm.expectRevert(); // ERC20InsufficientAllowance from OpenZeppelin
        desk.deposit(address(ausd), 5e6);
    }

    function test_withdraw_returnsUnclaimedBalance() public {
        _deposit(100e6);
        vm.expectEmit(true, true, false, true);
        emit Withdrawn(vendor, address(usdc), 40e6);
        vm.prank(vendor);
        desk.withdraw(address(usdc), 40e6);
        assertEq(desk.balanceOf(vendor, address(usdc)), 60e6);
        assertEq(usdc.balanceOf(vendor), 10_000e6 - 100e6 + 40e6);
    }

    function test_withdraw_cannotExceedBalance() public {
        _deposit(100e6);
        vm.prank(vendor);
        vm.expectRevert(BundleDesk.InsufficientBalance.selector);
        desk.withdraw(address(usdc), 100e6 + 1);
    }

    function test_withdraw_cannotTouchAnotherVendorsFunds() public {
        _deposit(100e6);
        vm.prank(attacker);
        vm.expectRevert(BundleDesk.InsufficientBalance.selector);
        desk.withdraw(address(usdc), 1);
    }

    // ---------- claim ----------

    function test_claim_paysRecipientOnce() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        vm.expectEmit(true, true, true, true);
        emit Claimed(vendor, guest, address(usdc), 20e6, voucher);
        _claim(v, guest);

        assertEq(usdc.balanceOf(guest), 20e6);
        assertEq(desk.balanceOf(vendor, address(usdc)), 80e6);
        assertEq(usdc.balanceOf(address(desk)), 80e6, "desk holds exactly the vendors' unclaimed balances");
        assertTrue(desk.claimed(_vDigest(v)));
    }

    function test_claim_secondClaimReverts() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        _claim(v, guest);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, guest, voucherKey);
        vm.expectRevert(BundleDesk.AlreadyClaimed.selector);
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, guest, vs, cs);
    }

    function test_claim_expiredReverts() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, guest, voucherKey);
        vm.warp(v.expiry); // exactly at expiry still valid
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, guest, vs, cs);

        V memory w = _v(20e6);
        w.voucher = vm.addr(0x70D);
        w.expiry = block.timestamp + 10;
        bytes memory ws = _vendorSig(w, vendorKey);
        bytes memory wc =
            _sig(0x70D, _digest(deskDomain, keccak256(abi.encode(desk.CLAIM_TYPEHASH(), _vDigest(w), guest))));
        vm.warp(w.expiry + 1);
        vm.expectRevert(BundleDesk.Expired.selector);
        desk.claim(w.vendor, w.token, w.amount, w.voucher, w.expiry, guest, ws, wc);
    }

    function test_claim_voucherNotSignedByVendorReverts() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        bytes memory forged = _vendorSig(v, attackerKey);
        bytes memory cs = _claimSig(v, guest, voucherKey);
        vm.expectRevert(BundleDesk.BadVendorSig.selector);
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, guest, forged, cs);
    }

    function test_claim_relayerCannotInflateAmount() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, guest, voucherKey);
        vm.expectRevert(BundleDesk.BadVendorSig.selector);
        desk.claim(v.vendor, v.token, 90e6, v.voucher, v.expiry, guest, vs, cs);
    }

    function test_claim_relayerCannotRedirectRecipient() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, guest, voucherKey); // voucher key signed "pay guest"
        vm.expectRevert(BundleDesk.BadClaimSig.selector);
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, attacker, vs, cs);
    }

    function test_claim_wrongVoucherKeyReverts() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, attacker, attackerKey); // someone who never held the voucher
        vm.expectRevert(BundleDesk.BadClaimSig.selector);
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, attacker, vs, cs);
    }

    function test_claim_cannotBorrowAnotherVendorsVoucher() public {
        _deposit(100e6);
        usdc.mint(attacker, 100e6);
        vm.startPrank(attacker);
        usdc.approve(address(desk), type(uint256).max);
        desk.deposit(address(usdc), 100e6);
        vm.stopPrank();

        V memory v = _v(20e6); // vendor's voucher
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, guest, voucherKey);
        // Present it as if the attacker issued it: digest differs, so the vendor signature fails.
        vm.expectRevert(BundleDesk.BadVendorSig.selector);
        desk.claim(attacker, v.token, v.amount, v.voucher, v.expiry, guest, vs, cs);
    }

    function test_claim_vendorWithdrewFirstReverts() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        vm.prank(vendor);
        desk.withdraw(address(usdc), 100e6);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, guest, voucherKey);
        vm.expectRevert(BundleDesk.InsufficientBalance.selector);
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, guest, vs, cs);
    }

    function test_claim_zeroRecipientReverts() public {
        _deposit(100e6);
        V memory v = _v(20e6);
        bytes memory vs = _vendorSig(v, vendorKey);
        bytes memory cs = _claimSig(v, address(0), voucherKey);
        vm.expectRevert(BundleDesk.ZeroAddress.selector);
        desk.claim(v.vendor, v.token, v.amount, v.voucher, v.expiry, address(0), vs, cs);
    }

    function testFuzz_conservation(uint96 depositAmt, uint96 claimAmt) public {
        depositAmt = uint96(bound(depositAmt, 1, 10_000e6));
        claimAmt = uint96(bound(claimAmt, 1, depositAmt));
        _deposit(depositAmt);
        V memory v = _v(claimAmt);
        _claim(v, guest);
        assertEq(usdc.balanceOf(guest), claimAmt);
        assertEq(usdc.balanceOf(address(desk)), desk.balanceOf(vendor, address(usdc)), "token balance equals ledger");
        assertEq(desk.balanceOf(vendor, address(usdc)), depositAmt - claimAmt);
    }
}
