// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// TEST-ONLY helper contracts. They exist so the unit tests can check how PlexusEscrowV2 behaves with
// unusual tokens and with smart-contract wallets. They are never deployed to a public network.

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// A token that burns 1% on every transfer: the escrow must refuse it (TransferMismatch).
contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee On Transfer", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

interface ITokenHook {
    function onTokenReceived() external;
}

/// A token that calls the receiver right after paying it (like ERC-777 hooks). It lets a test try to
/// re-enter the escrow while the escrow is in the middle of a withdrawal.
contract HookToken is ERC20 {
    constructor() ERC20("Hook Token", "HOOK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0) && to.code.length > 0) {
            try ITokenHook(to).onTokenReceived() {} catch {}
        }
    }
}

/// A token that can refuse payments to chosen addresses (like a USDT blacklist).
contract BlockableToken is ERC20 {
    mapping(address => bool) public blocked;

    constructor() ERC20("Blockable Token", "BLK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[to], "recipient blocked");
        super._update(from, to, value);
    }
}

/// A minimal smart-contract wallet: it can call any contract (like a Safe or any account contract)
/// and, when armed, tries to re-enter a target from inside a token payment.
contract ContractWallet is ITokenHook {
    bool public armed;
    address public target;
    bytes public payload;
    bool public reentered; // the re-entrant call succeeded
    bool public reentryBlocked; // the re-entrant call was refused

    function exec(address to, bytes calldata data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = to.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function arm(address to, bytes calldata data) external {
        armed = true;
        target = to;
        payload = data;
    }

    function onTokenReceived() external override {
        if (!armed) return;
        armed = false;
        (bool ok,) = target.call(payload);
        reentered = ok;
        reentryBlocked = !ok;
    }
}
