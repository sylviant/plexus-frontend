// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-network stand-in for Binance-Peg BSC-USD (18 decimals). Never deploy on mainnet.
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock BSC-USD", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
