// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.6.11;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal ReaperVaultV2 implementation.
contract ReaperVaultV2Minimal is ERC20 {
    using SafeERC20 for ERC20;

    ERC20 public immutable token;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) public ERC20(_name, _symbol) {
        token = _asset;
    }

    function deposit(uint256 _amount) external {
        require(_amount != 0, "Invalid amount");
        uint256 pool = balance();
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 shares;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / pool;
        }
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 _shares) external {
        require(_shares != 0, "Invalid amount");
        uint256 value = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);
        token.safeTransfer(msg.sender, value);
    }

    function balance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function decimals() public view override returns (uint8) {
        return token.decimals();
    }
}
